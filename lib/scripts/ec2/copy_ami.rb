require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"

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
    ec2_helper = Ec2Helper.new(@input_params[:ec2_api_handler])
    if ec2_helper.ami_prop(@input_params[:ami_id], 'rootDeviceType') != "ebs"
      raise Exception.new("must be an EBS type image")
    end
    local_ec2_helper = ec2_helper
    if !local_ec2_helper.check_open_port('default', 22)
      raise Exception.new("Port 22 must be opened for security group 'default' to connect via SSH in source-region")
    end
    remote_ec2_helper = Ec2Helper.new(@input_params[:target_ec2_handler])
    if !remote_ec2_helper.check_open_port('default', 22)
      raise Exception.new("Port 22 must be opened for security group 'default' to connect via SSH in target-region")
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
      @context[:source_instance_id], @context[:source_dns_name], @context[:source_availability_zone], 
        @context[:kernel_id], @context[:ramdisk_id], @context[:architecture] =
        launch_instance(@context[:ami_id], @context[:source_key_name], "default")
      ec2_helper = Ec2Helper.new(@context[:ec2_api_handler])
      puts "get_attached returns: #{ec2_helper.get_attached_volumes(@context[:source_instance_id]).inspect}"
      @context[:ebs_volume_id] = ec2_helper.get_attached_volumes(@context[:source_instance_id])[0]['volumeId']#TODO: what when more root devices?
      SourceInstanceLaunchedState.new(@context)
    end
  end

 # Source is started. Create a snapshot on the volume that is linked to the instance.
  class SourceInstanceLaunchedState < CopyAmiState
    def enter()
      @context[:snapshot_id] = create_snapshot(@context[:ebs_volume_id], "Cloudy_Scripts Snapshot for copying AMIs")
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
      result = launch_instance(@context[:target_ami_id], @context[:target_key_name], 
        "default")
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
      upload_file(@context[:source_dns_name], @context[:source_ssh_username], @context[:source_ssh_keydata],
        @context[:target_ssh_keyfile], "#{key_path}#{@context[:target_key_name]}.pem")
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
      remote_copy(@context[:source_ssh_username], @context[:target_key_name], source_dir, 
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
      @context[:new_snapshot_id] = create_snapshot(@context[:target_volume_id], "Created by Cloudy_Scripts - copy_snapshot")
      TargetSnapshotCreatedState.new(@context)
    end
  end

  # Snapshot Operation done. Now this snapshot must be registered as AMI
  class TargetSnapshotCreatedState < CopyAmiState
    def enter()
      remote_region()
      # Get Amazon Kernel Image ID
      #aki = get_aws_kernel_image_aki(@context[:ec2_api_handler].server.split('.')[0], @context[:kernel_id], 
      #  @context[:target_ec2_handler].server.split('.')[0])
      aki = get_aws_kernel_image_aki(@context[:ec2_api_handler].server, @context[:kernel_id], 
        @context[:target_ec2_handler].server)
      #@context[:result][:image_id] = register_snapshot(@context[:new_snapshot_id], @context[:name],
      #  @context[:root_device_name], @context[:description], nil,
      #  nil, @context[:architecture])
      @context[:result][:image_id] = register_snapshot(@context[:new_snapshot_id], @context[:name],
        @context[:root_device_name], @context[:description], aki,
        nil, @context[:architecture])
      AmiRegisteredState.new(@context)
    end
  end

  # AMI is registered. Now only cleanup is missing, i.e. shut down instances and
  # remote the volumes that were created. Start with cleaning the ressources
  # in the local region.
  class AmiRegisteredState < CopyAmiState
    def enter()
      local_region()
      shut_down_instance(@context[:source_instance_id])
      delete_volume(@context[:source_volume_id])
      delete_snapshot(@context[:snapshot_id])
      SourceCleanedUpState.new(@context)
    end
  end

  # Cleanup the resources in the target region.
  class SourceCleanedUpState < CopyAmiState
    def enter()
      remote_region()
      shut_down_instance(@context[:target_instance_id])
      delete_volume(@context[:target_volume_id])
      Done.new(@context)
    end
  end

end
