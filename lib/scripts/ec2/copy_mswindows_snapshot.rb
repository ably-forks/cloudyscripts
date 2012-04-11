require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"
require 'pp'

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

class CopyMsWindowsSnapshot < Ec2Script
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
    @local_ec2_helper = Ec2Helper.new(@input_params[:ec2_api_handler])
    @remote_ec2_helper = Ec2Helper.new(@input_params[:target_ec2_handler]) 
  end

  def check_input_parameters()
    if @input_params[:snapshot_id] == nil && !(@input_params[:snapshot_id] =~ /^snap-.*$/)
      raise Exception.new("Invalid Snapshot ID specified: #{@input_params[:snapshot_id]}")
    end
    if @input_params[:source_ami_id] == nil && !(@input_params[:source_ami_id] =~ /^ami-.*$/)
      raise Exception.new("Invalid source AMI ID specified: #{@input_params[:source_ami_id]}")
    end
    if @input_params[:target_ami_id] == nil && !(@input_params[:target_ami_id] =~ /^ami-.*$/)
      raise Exception.new("Invalid target AMI ID specified: #{@input_params[:target_ami_id]}")
    end
    if @input_params[:source_security_groups] == nil
      @input_params[:source_security_groups] = "default"
    end
    if !@local_ec2_helper.check_open_port(@input_params[:source_security_groups], 22)
      raise Exception.new("Port 22 must be opened for security group '#{@input_params[:source_security_groups]}' to connect via SSH in source-region")
    end
    if @input_params[:target_security_groups] == nil
      @input_params[:target_security_groups] = "default"
    end
    if !@remote_ec2_helper.check_open_port(@input_params[:target_security_groups], 22)
      raise Exception.new("Port 22 must be opened for security group '#{@input_params[:target_security_groups]}' to connect via SSH in target-region")
    end
    if @input_params[:root_device_name] == nil
      @input_params[:root_device_name] = "/dev/sda1"
    end
    if @input_params[:device_name] == nil
      @input_params[:device_name] = "/dev/sdj"
    end
    if @input_params[:temp_device_name] == nil
      @input_params[:temp_device_name] = "/dev/sdk"
    end
    if @input_params[:temp_device_name] == @input_params[:device_name]
      raise Exception.new("Device name '#{@input_params[:device_name]}' and temporary device name '#{@input_params[:temp_device_name]}' must be different")
    end
    if @input_params[:source_ssh_username] == nil
      @input_params[:source_ssh_username] = "root"
    end
    if @input_params[:target_ssh_username] == nil
      @input_params[:target_ssh_username] = "root"
    end
    if @input_params[:fs_type] == nil
      @input_params[:fs_type] = "ext3"
    end
    if @input_params[:description] == nil
      @input_params[:description] = "Created by Cloudy_Scripts - copy_mswindows_snapshot"
    end
  end

  # Load the initial state for the script.
  # Abstract method to be implemented by extending classes.
  def load_initial_state()
    CopyMsWindowsSnapshotState.load_state(@input_params)
  end

  private

  # Here begins the state machine implementation
  class CopyMsWindowsSnapshotState < ScriptExecutionState

    def self.load_state(context)
      InitialState.new(context)
    end

    def local_region
      self.ec2_handler = (@context[:ec2_api_handler])
      @local_ec2_helper = Ec2Helper.new(self.ec2_handler)
    end

    def remote_region
      self.ec2_handler = (@context[:target_ec2_handler])
      @remote_ec2_helper = Ec2Helper.new(self.ec2_handler)
    end
  end

  # Initial State: Retrieve all information on this AMI we need later on 
  #                and set some parameters such as the Availability Zone
  #   - Snapshot ID from this AMI
  #   - Volume size from this AMI
  #   - Availability Zone 
  #NB: less modification if we get the AZ from the launched instance
  class InitialState < CopyMsWindowsSnapshotState 
    def enter()
      local_region()
      post_message("Retrieving Snapshot parammeters (volume size)")
      @context[:volume_size] = @local_ec2_helper.snapshot_prop(@context[:snapshot_id], :volumeSize).to_i
  
      InitialStateDone.new(@context)
    end
  end

  # Initial state: Launch an Amazon Linux AMI in the source Region
  class InitialStateDone < CopyMsWindowsSnapshotState 
    def enter()
      local_region()
      post_mesage("Lunching an Helper instance in source Region...")
      result = launch_instance(@context[:source_ami_id], @context[:source_key_name], @context[:source_security_groups])
      @context[:source_instance_id] = result.first
      @context[:source_dns_name] = result[1]
      @context[:source_availability_zone] = result[2]
      @context[:source_root_device_name] = result[6]

      SourceInstanceLaunchedState.new(@context)
    end
  end

  # Source instance is started.
  # Steps:
  #   - create and attach a volume from the Snapshot of the AMI to copy
  #   - create and attach a temp volume of the same size to dump and compress the entire drive
  #   - create a filesystem on the temp volume and mount the temp volume
  #   - dump and compress the entire drive to the temp volume
  class SourceInstanceLaunchedState < CopyMsWindowsSnapshotState
    def enter()
      local_region()
      # Step1: create and attach a volume from the Snapshot of the AMI to copy
      @context[:source_volume_id] = create_volume_from_snapshot(@context[:snapshot_id],
        @context[:source_availability_zone])
      source_device = @context[:device_name]
      attach_volume(@context[:source_volume_id], @context[:source_instance_id], source_device)
      connect(@context[:source_dns_name], @context[:source_ssh_username], nil, @context[:source_ssh_keydata]) 
      # detect if there is a shift for device mapping (between AWS and the operating system of the system)
      root_device_name = get_root_device_name()
      # detect letters
      aws_root_device = @context[:source_root_device_name]
      aws_letter = aws_root_device.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      os_letter = root_device_name.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      aws_device_letter = source_device.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      if !aws_letter.eql?(os_letter)
        post_message("Detected specific kernel with shift between AWS and Kernel OS for device naming")
      end
      while !aws_letter.eql?(os_letter)
        aws_letter.succ!
        aws_device_letter.succ!
      end
      source_device = "/dev/sd#{aws_device_letter}"
      post_message("Using AWS name source device '#{@context[:device_name]}' and OS name '#{source_device}'")
      @context[:source_device_name] = source_device
      # Step2: create and attach a temp volume of the same size to dump and compress the entire drive
      @context[:source_temp_volume_id] = create_volume(@context[:source_availability_zone], @context[:volume_size])
      temp_device = @context[:temp_device_name] 
      attach_volume(@context[:source_temp_volume_id], @context[:source_instance_id], temp_device)
      aws_device_letter = temp_device.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      while !aws_letter.eql?(os_letter)
        aws_letter.succ!
        aws_device_letter.succ!
      end
      temp_device="/dev/sd#{aws_device_letter}" 
      post_message("Using AWS name source device '#{@context[:temp_device_name]}' and OS name '#{temp_device}'") 
      # Step3: mount the temp volume
      mount_point = "/mnt/tmp_#{@context[:source_temp_volume_id]}"
      create_labeled_fs(@context[:source_dns_name], temp_device, @context[:fs_type], nil)
      mount_fs(mount_point, temp_device)
      disconnect()

      SourceVolumeReadyState.new(@context)
    end
  end

  # Source is ready
  # Steps:
  #   - dump and compress the entire source drive to the temp volume
  class SourceVolumeReadyState < CopyMsWindowsSnapshotState
    def enter()
      local_region()
      connect(@context[:source_dns_name], @context[:source_ssh_username], nil, @context[:source_ssh_keydata])
      mount_point = "/mnt/tmp_#{@context[:source_temp_volume_id]}"
      @context[:source_filename] = "#{mount_point}" + "/" + "#{@context[:snapshot_id]}" + ".gz"
      local_dump_and_compress_device_to_file(@context[:source_device_name], @context[:source_filename])
      disconnect()

      BackupedDataState.new(@context)
    end
  end

  # Source is ready.
  # Steps:
  #   - start an instance of AWS Linux AMI in the target region
  class BackupedDataState < CopyMsWindowsSnapshotState 
    def enter()
      remote_region()
      result = launch_instance(@context[:target_ami_id], @context[:target_key_name], @context[:target_security_groups])
      @context[:target_instance_id] = result.first
      @context[:target_dns_name] = result[1]
      @context[:target_availability_zone] = result[2]
      @context[:target_root_device_name] = result[6]

      TargetInstanceLaunchedState.new(@context)
    end
  end

  # Destination instance is started. Now configure storage.
  # Steps:
  #   - create and attach a temp volume for receiving archive of the drive
  #   - create a filesystem on the temp volume and mount the temp volume
  #   - create and attach a volume for uncompressing and restoring the entire drive 
  class TargetInstanceLaunchedState < CopyMsWindowsSnapshotState
    def enter()
      remote_region()
      # Step1: create and attach a temp volume for receiving archive of the drive
      @context[:target_temp_volume_id] = create_volume(@context[:target_availability_zone], @context[:volume_size])
      temp_device = @context[:temp_device_name] 
      attach_volume(@context[:target_temp_volume_id], @context[:target_instance_id], temp_device)
      connect(@context[:target_dns_name], @context[:target_ssh_username], nil, @context[:target_ssh_keydata]) 
      # detect if there is a shift for device mapping (between AWS and the operating system of the system)
      root_device_name = get_root_device_name()
      # detect letters
      aws_root_device = @context[:target_root_device_name]
      aws_letter = aws_root_device.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      os_letter = root_device_name.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      aws_device_letter = temp_device.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      if !aws_letter.eql?(os_letter)
        post_message("Detected specific kernel with shift between AWS and Kernel OS for device naming")
      end
      while !aws_letter.eql?(os_letter)
        aws_letter.succ!
        aws_device_letter.succ!
      end
      temp_device = "/dev/sd#{aws_device_letter}"
      post_message("Using AWS name source device '#{@context[:device_name]}' and OS name '#{temp_device}'")
      # Step2: mount the temp volume
      mount_point = "/mnt/tmp_#{@context[:target_temp_volume_id]}"
      create_labeled_fs(@context[:target_dns_name], temp_device, @context[:fs_type], nil)
      mount_fs(mount_point, temp_device)
      # Step3: create and attach a volume for uncompressing and restoring the entire drive
      @context[:target_volume_id] = create_volume(@context[:target_availability_zone], @context[:volume_size])
      target_device = @context[:device_name]
      attach_volume(@context[:target_volume_id], @context[:target_instance_id], target_device)
      aws_device_letter = target_device.split('/')[2].gsub('sd', '').gsub('xvd', '').gsub(/[0-9]/, '')
      if !aws_letter.eql?(os_letter)
        post_message("Detected specific kernel with shift between AWS and Kernel OS for device naming")
      end
      while !aws_letter.eql?(os_letter)
        aws_letter.succ!
        aws_device_letter.succ!
      end
      target_device = "/dev/sd#{aws_device_letter}"
      @context[:target_device_name] = target_device
      post_message("Using AWS name source device '#{@context[:device_name]}' and OS name '#{target_device}'")
      disconnect()

      TargetVolumeReadyState.new(@context)
    end
  end

  # Storages are ready. Only thing missing: the key of the target region
  # must be available on the instance in the source region to be able to perform
  # a remote copy.
  class TargetVolumeReadyState < CopyMsWindowsSnapshotState
    def enter()
      post_message("upload key of target-instance to source-instance...")
      path_candidates = ["/#{@context[:source_ssh_username]}/.ssh/", "/home/#{@context[:source_ssh_username]}/.ssh/"]
      key_path = determine_file(@context[:source_dns_name], @context[:source_ssh_username], @context[:source_ssh_keydata], path_candidates)
      #XXX: fix the problem fo key name with white space
      #upload_file(@context[:source_dns_name], @context[:source_ssh_username], @context[:source_ssh_keydata],
      #  @context[:target_ssh_keyfile], "#{key_path}#{@context[:target_key_name]}.pem")
      upload_file(@context[:source_dns_name], @context[:source_ssh_username], @context[:source_ssh_keydata],
        @context[:target_ssh_keyfile], "#{key_path}#{@context[:target_key_name].gsub(/\s+/, '_')}.pem")
      post_message("credentials are in place to connect source and target (from source to target).")

      KeyInPlaceState.new(@context)
    end
  end

  # Now we can copy.
  class KeyInPlaceState < CopyMsWindowsSnapshotState
    def enter()
      connect(@context[:target_dns_name], @context[:target_ssh_username], nil, @context[:target_ssh_keydata])
      disable_ssh_tty(@context[:target_dns_name])
      disconnect()
      #
      connect(@context[:source_dns_name], @context[:source_ssh_username], nil, @context[:source_ssh_keydata])
      source_dir = "/mnt/tmp_#{@context[:source_temp_volume_id]}/"
      dest_dir = "/mnt/tmp_#{@context[:target_temp_volume_id]}/"
      #XXX: fix the problem fo key name with white space
      #remote_copy(@context[:source_ssh_username], @context[:target_key_name], source_dir, 
      #  @context[:target_dns_name], @context[:target_ssh_username], dest_dir)
      remote_copy(@context[:source_ssh_username], @context[:target_key_name].gsub(/\s+/, '_'), source_dir, 
        @context[:target_dns_name], @context[:target_ssh_username], dest_dir)

      disconnect()
      #
      connect(@context[:target_dns_name], @context[:target_ssh_username], nil, @context[:target_ssh_keydata])
      enable_ssh_tty(@context[:target_dns_name])
      disconnect()

      DataCopiedState.new(@context)
    end
  end

  # Decompress data on the device
  class DataCopiedState < CopyMsWindowsSnapshotState
    def enter()
      remote_region()
      connect(@context[:target_dns_name], @context[:target_ssh_username], nil, @context[:target_ssh_keydata])
      mount_point = "/mnt/tmp_#{@context[:target_temp_volume_id]}"
      @context[:source_filename] = "#{mount_point}" + "/" + "#{@context[:snapshot_id]}" + ".gz"
      local_decompress_and_dump_file_to_device(@context[:source_filename], @context[:target_device_name])
      disconnect()

      RestoredDataState.new(@context)
    end
  end

  # Data of snapshot now copied to the new volume.
  # Steps:
  #   - detach the target volume
  #XXX: TODO
  class RestoredDataState < CopyMsWindowsSnapshotState
    def enter()
      remote_region()
      detach_volume(@context[:target_volume_id], @context[:target_instance_id])
      #@context[:new_snapshot_id] = create_snapshot(@context[:target_volume_id], "Created by CloudyScripts - copy_mswindows_ami")
      @context[:new_snapshot_id] = create_snapshot(@context[:target_volume_id], @context[:description])
      @context[:result][:snapshot_id] = @context[:new_snapshot_id]

      TargetSnapshotCreatedState.new(@context)
    end
  end

  # AMI is registered. Now only cleanup is missing, i.e. shut down instances and
  # remote the volumes that were created. Start with cleaning the ressources
  # in the local region.
  # Steps:
  #   - cleanup source region
  #     - unmount temp volume
  #     - detach source and temp volume
  #     - terminate instance
  #     - delete source and temp volume
  #   - cleanup target region
  #     - unmount temp volume
  #     - detach temp volume
  #     - terminate instance
  #     - delete source and temp volume
  class TargetSnapshotCreatedState < CopyMsWindowsSnapshotState
    def enter()
      local_region()
      connect(@context[:source_dns_name], @context[:source_ssh_username], nil, @context[:source_ssh_keydata])
      mount_point = "/mnt/tmp_#{@context[:source_temp_volume_id]}"
      unmount_fs(mount_point)
      disconnect()
      detach_volume(@context[:source_temp_volume_id], @context[:source_instance_id])
      detach_volume(@context[:source_volume_id], @context[:source_instance_id])
      shut_down_instance(@context[:source_instance_id])
      delete_volume(@context[:source_temp_volume_id])
      delete_volume(@context[:source_volume_id])
      #
      remote_region()
      connect(@context[:target_dns_name], @context[:target_ssh_username], nil, @context[:target_ssh_keydata])
      mount_point = "/mnt/tmp_#{@context[:target_temp_volume_id]}"
      unmount_fs(mount_point)
      disconnect()
      detach_volume(@context[:target_temp_volume_id], @context[:target_instance_id])
      shut_down_instance(@context[:target_instance_id])
      delete_volume(@context[:target_temp_volume_id])
      delete_volume(@context[:target_volume_id])
 
      Done.new(@context)
    end
  end

end
