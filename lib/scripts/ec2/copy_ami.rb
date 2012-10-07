require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"
require "help/helper"


# Copy a given snapshot to another region
# * start up instance in source-region, create a snapshot from the mounted EBS
# * then create volume from snapshot, attach volume, and mount it
# * start up instance in destination-region, create empty volume of same size, attache volume, and mount it
# * copy the destination key to the source instance
# * perform an rsynch
#   sync -PHAXaz --rsh "ssh -i /home/${src_user}/.ssh/id_${dst_keypair}" --rsync-path "sudo rsync" ${src_dir}/ ${dst_user}@${dst_public_fqdn}:${dst_dir}/
# * create a snapshot of the volume
# * register the snapshot as AMI
# * clean-up everything

class CopyAmi < Ec2Script
  # context information needed
  # * the EC2 credentials (see #Ec2Script)
  # * ami_id => the ID of the AMI to be copied in another region
  # * target_ec2_handler => The EC2 handler connected to the region where the snapshot is being copied to
  # * source_ssh_username => The username for ssh for source-instance (default = root)
  # * source_key_name => Key name of the instance that manages the snaphot-volume in the source region
  # * source_ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]
  # * source_ssh_key_files => Key information for the security group that starts the AMI
  # * target_ssh_username => The username for ssh for target-instance (default = root)
  # * target_key_name => Key name of the instance that manages the snaphot-volume in the target region
  # * target_ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]
  # * target_ssh_key_files => Key information for the security group that starts the AMI
  # * target_ami_id => ID of the AMI to start in the target region
  # * name => name of new AMI to be created
  # * description => description of new AMI to be created
  
  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:ami_id] == nil && !(@input_params[:ami_id] =~ /^ami-.*$/)
      raise Exception.new("Invalid AMI ID specified: #{@input_params[:ami_id]}")
    end
    ec2_helper = Ec2Helper.new(@input_params[:ec2_api_handler])
    if ec2_helper.ami_prop(@input_params[:ami_id], 'rootDeviceType') != "ebs"
      raise Exception.new("must be an EBS type image")
    end
    local_ec2_helper = ec2_helper
    if @input_params[:source_security_group] == nil
      @input_params[:source_security_group] = "default"
    end
    if !local_ec2_helper.check_open_port(@input_params[:source_security_group], 22)
      post_message("'#{@input_params[:source_security_group]}' Security Group not opened port 22 for connect via SSH in source region")
      @input_params[:source_security_group] = nil
    else
      post_message("'#{@input_params[:source_security_group]}' Security Group opened port 22 for connect via SSH in source region")
    end
    remote_ec2_helper = Ec2Helper.new(@input_params[:target_ec2_handler])
    if @input_params[:target_security_group] == nil
      @input_params[:target_security_group] = "default"
    end
    if !remote_ec2_helper.check_open_port(@input_params[:target_security_group], 22)
      post_message("'#{@input_params[:target_security_group]}' Security Group not opened port 22 for connect via SSH in target region")
      @input_params[:target_security_group] = nil
    else
      post_message("'#{@input_params[:target_security_group]}' Security Group opened port 22 for connect via SSH in target region")
    end
    if @input_params[:root_device_name] == nil
      @input_params[:root_device_name] = "/dev/sda1"
    end
    if @input_params[:temp_device_name] == nil
      @input_params[:temp_device_name] = "/dev/sdj"
    end
    if @input_params[:source_ssh_username] == nil
      @input_params[:source_ssh_username] = "root"
    end
    if @input_params[:target_ssh_username] == nil
      @input_params[:target_ssh_username] = "root"
    end
    if @input_params[:description] == nil || !check_aws_desc(@input_params[:description])
      @input_params[:description] = "Created by CloudyScripts - #{self.class.name}"
    end
    if @input_params[:name] == nil || !check_aws_name(@input_params[:name])
      @input_params[:name] = "Created_by_CloudyScripts/#{self.class.name}_from_#{@input_params[:ami_id]}"
    end
  end

  # Load the initial state for the script.
  # Abstract method to be implemented by extending classes.
  def load_initial_state()
    CopyAmiState.load_state(@input_params)
  end

  private

  # Here begins the state machine implementation
  class CopyAmiState < ScriptExecutionState

    def self.load_state(context)
      InitialState.new(context)
    end

    def local_region
      self.ec2_handler=(@context[:ec2_api_handler])
    end

    def remote_region
      self.ec2_handler=(@context[:target_ec2_handler])
    end
  end

  # Initial state: start up AMI in source region
  class InitialState < CopyAmiState
    def enter()
      local_region()
      #XXX: create a CloudyScripts Security Group with TCP port 22 publicly opened
      if @context[:source_security_group] == nil
        @context[:source_security_group] = Ec2Script::CS_SEC_GRP_NAME
        create_security_group_with_rules(@context[:source_security_group], Ec2Script::CS_SEC_GRP_DESC, 
          [{:ip_protocol => "tcp", :from_port => 22, :to_port => 22, :cidr_ip => "0.0.0.0/0"}])
        post_message("'#{@context[:source_security_group]}' Security Group created with TCP port 22 publicly opened.")
      end

      @context[:source_instance_id], @context[:source_dns_name], @context[:source_availability_zone], 
        @context[:kernel_id], @context[:ramdisk_id], @context[:architecture], @context[:root_device_name] =
        launch_instance(@context[:ami_id], @context[:source_key_name], @context[:source_security_group])
      ec2_helper = Ec2Helper.new(@context[:ec2_api_handler])
      @context[:ebs_volume_id] = ec2_helper.get_attached_volumes(@context[:source_instance_id])[0]['volumeId']	#TODO: what when more root devices?

      SourceInstanceLaunchedState.new(@context)
    end
  end

  # Source is started. Create a snapshot on the volume that is linked to the instance.
  class SourceInstanceLaunchedState < CopyAmiState
    def enter()
      @context[:snapshot_id] = create_snapshot(@context[:ebs_volume_id], 
        "Created by CloudyScripts - #{self.get_superclass_name()} from #{@context[:ebs_volume_id]}")

      AmiSnapshotCreatedState.new(@context)
    end
  end

  # Snapshot is created from the AMI. Create a volume from the snapshot, attach and mount the volume as second device.
  class AmiSnapshotCreatedState < CopyAmiState
    def enter()
      @context[:source_volume_id] = create_volume_from_snapshot(@context[:snapshot_id],
        @context[:source_availability_zone])
      device = @context[:temp_device_name]
      mount_point = "/mnt/tmp_#{@context[:source_volume_id]}"
      attach_volume(@context[:source_volume_id], @context[:source_instance_id], device)
      connect(@context[:source_dns_name], @context[:source_ssh_username], nil, @context[:source_ssh_keydata]) 
      # detect if there is a shift for device mapping (between AWS and the operating system of the system)
      root_device_name = get_root_device_name()
      # detect letters
      aws_root_device = @context[:root_device_name]
      aws_letter = aws_root_device.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      os_letter = root_device_name.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      aws_device_letter = device.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      if !aws_letter.eql?(os_letter)
        post_message("Detected specific kernel with shift between AWS and Kernel OS for device naming: '#{aws_root_device}' vs '#{root_device_name}'")
      end
      while !aws_letter.eql?(os_letter)
        aws_letter.succ!
        aws_device_letter.succ!
      end

      device = "/dev/sd#{aws_device_letter}"
      # detect root partition vs root volume: simply check if we have several /dev/sdx* entries
      parts_count = get_partition_count(device)
      if parts_count >= 2
        # retrieve partition table, in order to restore it in the target region
        post_message("Detected specific volume with a valid partition table on device '#{device}'...")
        partition_table = get_partition_table(device)
        @context[:partition_table] = partition_table
        #XXX: HANDLE at a LOWER LEVEL
        # update partition table with device
        # s/device/@context[:temp_device_name]/ on partition table 
        #@context[:partition_table] = partition_table.gsub("#{device}", "#{@context[:temp_device_name]}")
        # retrieve the root partition number
        os_nb = root_device_name.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[a-z]/, '')
        device = device + os_nb
        @context[:root_partition_nb] = os_nb
        post_message("Using root partition: '#{device}'...")
      end
      post_message("Using AWS name '#{@context[:temp_device_name]}' and OS name '#{device}'")
      mount_fs(mount_point, device)
      # get root partition label and filesystem type
      #@context[:label] = get_root_partition_label()
      #@context[:fs_type] = get_root_partition_fs_type()
      @context[:fs_type], @context[:label] = get_root_partition_fs_type_and_label()
      disconnect()

      SourceVolumeReadyState.new(@context)
    end
  end

  # Source is ready. Now start instance in the target region
  class SourceVolumeReadyState < CopyAmiState
    def enter()
      remote_region()
      #XXX: create a CloudyScripts Security Group with TCP port 22 publicly opened
      if @context[:target_security_group] == nil
        @context[:target_security_group] = Ec2Script::CS_SEC_GRP_NAME
        create_security_group_with_rules(@context[:target_security_group], Ec2Script::CS_SEC_GRP_DESC, 
          [{:ip_protocol => "tcp", :from_port => 22, :to_port => 22, :cidr_ip => "0.0.0.0/0"}])
        post_message("'#{@context[:target_security_group]}' Security Group created with TCP port 22 publicly opened.")
      end

      result = launch_instance(@context[:target_ami_id], @context[:target_key_name], @context[:target_security_group])
      @context[:target_instance_id] = result.first
      @context[:target_dns_name] = result[1]
      @context[:target_availability_zone] = result[2]

      TargetInstanceLaunchedState.new(@context)
    end
  end

  # Destination instance is started. Now configure storage.
  class TargetInstanceLaunchedState < CopyAmiState
    def enter()
      local_region()
      ec2_helper = Ec2Helper.new(@context[:ec2_api_handler])
      volume_size = ec2_helper.snapshot_prop(@context[:snapshot_id], :volumeSize).to_i
      #
      remote_region()
      @context[:target_volume_id] = create_volume(@context[:target_availability_zone], volume_size)
      device = @context[:temp_device_name]
      mount_point = "/mnt/tmp_#{@context[:target_volume_id]}"
      attach_volume(@context[:target_volume_id], @context[:target_instance_id], device)
      connect(@context[:target_dns_name], @context[:target_ssh_username], nil, @context[:target_ssh_keydata])
      # check if we need to create a partition table
      if !(@context[:partition_table] == nil)
        post_message("Creating a partition table on device '#{device}'...")
        set_partition_table(device, @context[:partition_table])
        #XXX: HANDLE at a LOWER LEVEL
        # before adding partition table, adjust device name
        #set_partition_table(device, @context[:partition_table].gsub(/\/dev\/(s|xv)d[a-z]/, "#{@context[:temp_device_name]}"))
        # adjust partition to mount
        device = device + @context[:root_partition_nb]
      end
      # make root partition
      create_labeled_fs(@context[:target_dns_name], device, @context[:fs_type], @context[:label])
      mount_fs(mount_point, device)
      disconnect()

      TargetVolumeReadyState.new(@context)
    end
  end

  # Storages are ready. Only thing missing: the key of the target region
  # must be available on the instance in the source region to be able to perform
  # a remote copy.
  class TargetVolumeReadyState < CopyAmiState
    def enter()
      post_message("upload key of target-instance to source-instance...")
      path_candidates = ["/#{@context[:source_ssh_username]}/.ssh/",
        "/home/#{@context[:source_ssh_username]}/.ssh/"]
      key_path = determine_file(@context[:source_dns_name], @context[:source_ssh_username], @context[:source_ssh_keydata], path_candidates)
      #XXX: fix the problem fo key name with white space
      #upload_file(@context[:source_dns_name], @context[:source_ssh_username], @context[:source_ssh_keydata],
      #  @context[:target_ssh_keyfile], "#{key_path}#{@context[:target_key_name]}.pem")
      upload_file(@context[:source_dns_name], @context[:source_ssh_username], @context[:source_ssh_keydata],
        @context[:target_ssh_keyfile], "#{key_path}#{@context[:target_key_name].gsub(/\s+/, '_')}.pem")
      post_message("credentials are in place to connect source and target.")

      KeyInPlaceState.new(@context)
    end
  end

  # Now we can copy.
  class KeyInPlaceState < CopyAmiState
    def enter()
      connect(@context[:target_dns_name], @context[:target_ssh_username], nil, @context[:target_ssh_keydata])
      disable_ssh_tty(@context[:target_dns_name])
      disconnect()
      #
      connect(@context[:source_dns_name], @context[:source_ssh_username], nil, @context[:source_ssh_keydata])
      source_dir = "/mnt/tmp_#{@context[:source_volume_id]}/"
      dest_dir = "/mnt/tmp_#{@context[:target_volume_id]}"
      #XXX: fix the problem fo key name with white space
      #remote_copy(@context[:source_ssh_username], @context[:target_key_name], source_dir, 
      #  @context[:target_dns_name], @context[:target_ssh_username], dest_dir)
      remote_copy(@context[:source_ssh_username], @context[:target_key_name].gsub(/\s+/, '_'), source_dir, 
        @context[:target_dns_name], @context[:target_ssh_username], dest_dir)
      disconnect()
      #
      connect(@context[:target_dns_name], @context[:target_ssh_username], nil, @context[:target_ssh_keydata])
      enable_ssh_tty(@context[:target_dns_name])
      unmount_fs(dest_dir)
      disconnect()

      DataCopiedState.new(@context)
    end
  end

  # Data of snapshot now copied to the new volume. Create a snapshot of the
  # new volume.
  class DataCopiedState < CopyAmiState
    def enter()
      remote_region()
      @context[:new_snapshot_id] = create_snapshot(@context[:target_volume_id], 
        "Created by CloudyScripts - #{self.get_superclass_name()} from #{@context[:target_volume_id]}")

      TargetSnapshotCreatedState.new(@context)
    end
  end

  # Snapshot Operation done. Now this snapshot must be registered as AMI
  class TargetSnapshotCreatedState < CopyAmiState
    def enter()
      remote_region()
      # Get Amazon Kernel Image ID
      aki = get_aws_kernel_image_aki(@context[:source_availability_zone], @context[:kernel_id],
        @context[:target_availability_zone])
      device = @context[:root_device_name]
      if !(@context[:partition_table] == nil)
        device.gsub!(/[0-9]/, '')
        post_message("Using BlockDevice for snapshot registration rather than RootDevice '#{device}' due to a valid partition table on device...")
      end
      @context[:result][:image_id] = register_snapshot(@context[:new_snapshot_id], @context[:name],
        device, @context[:description], aki, nil, @context[:architecture])

      AmiRegisteredState.new(@context)
    end
  end

  # AMI is registered. Now only cleanup is missing, i.e. shut down instances and
  # remote the volumes that were created. Start with cleaning the ressources
  # in the both regions.
  class AmiRegisteredState < CopyAmiState
    def enter()
      error = []
      local_region()
      begin
        shut_down_instance(@context[:source_instance_id])
      rescue Exception => e
        error << e
        post_message("Unable to shutdown instance '#{@context[:source_instance_id]}' in source region: #{e.to_s}")
      end
      begin
        delete_volume(@context[:source_volume_id])
      rescue Exception => e
        error << e
        post_message("Unable to delete volume '#{@context[:source_volume_id]}' in source region: #{e.to_s}")
      end
      begin
        delete_snapshot(@context[:snapshot_id])
      rescue Exception => e
        error << e
        post_message("Unable to delete snapshot '#{@context[:snapshot_id]}' in source region: #{e.to_s}")
      end
      #XXX: delete Security Group according to its name
      if @context[:source_security_group].eql?(Ec2Script::CS_SEC_GRP_NAME)
        begin
          delete_security_group(@context[:source_security_group])
        rescue Exception => e
          error << e
          post_message("Unable to delete Security Group '#{@context[:source_security_group]}' in source region: #{e.to_s}")
        end
      end
      #
      remote_region()
      begin
        shut_down_instance(@context[:target_instance_id])
      rescue Exception => e
        error << e
        post_message("Unable to shutdown instance '#{@context[:target_instance_id]}' in target region: #{e.to_s}")
      end
      begin
        delete_volume(@context[:target_volume_id])
      rescue Exception => e
        error << e
        post_message("Unable to delete volume '#{@context[:target_volume_id]}' in target region: #{e.to_s}")
      end
      #XXX: delete Security Group according to its name
      if @context[:target_security_group].eql?(Ec2Script::CS_SEC_GRP_NAME)
        begin
          delete_security_group(@context[:target_security_group])
        rescue
          error << e
          post_message("Unable to delete Security Group '#{@context[:target_security_group]}' in target region: #{e.to_s}")
        end
      end

      if error.size() > 0
        raise Exception.new("Cleanup error(s)")
      end

      Done.new(@context)
    end
  end

end
