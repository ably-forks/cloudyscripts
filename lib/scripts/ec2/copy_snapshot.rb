require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"
require "help/helper"


# Copy a given snapshot to another region
# * start up instance in source-region, create volume from snapshot, attach volume, and mount it
# * start up instance in destination-region, create empty volume of same size, attache volume, and mount it
# * copy the destination key to the source instance
# * perform an rsynch
#   sync -PHAXaz --rsh "ssh -i /home/${src_user}/.ssh/id_${dst_keypair}" --rsync-path "sudo rsync" ${src_dir}/ ${dst_user}@${dst_public_fqdn}:${dst_dir}/
# * create a snapshot of the volume
# * clean-up everything

class CopySnapshot< Ec2Script
  # context information needed
  # * the EC2 credentials (see #Ec2Script)
  # * snapshot_id => The ID of the snapshot to be downloaded
  # * target_ec2_handler => The EC2 handler connected to the region where the snapshot is being copied to
  # * source_ssh_username => user name to connect to the source instance (default = root)
  # * source_key_name => Key name of the instance that manages the snaphot-volume in the source region
  # * source_ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]
  # * source_ssh_key_file => Key information for the security group that starts the AMI
  # * target_ssh_username => user name to connect to the target instance (default = root)
  # * target_key_name => Key name of the instance that manages the snaphot-volume in the target region
  # * target_ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]
  # * target_ssh_key_file => Key information for the security group that starts the AMI
  # * source_ami_id => ID of the AMI to start in the source region
  # * target_ami_id => ID of the AMI to start in the target region
  
  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    local_ec2_helper = Ec2Helper.new(@input_params[:ec2_api_handler])
    if !local_ec2_helper.check_open_port('default', 22)
      raise Exception.new("Port 22 must be opened for security group 'default' to connect via SSH in source-region")
    end
    remote_ec2_helper = Ec2Helper.new(@input_params[:target_ec2_handler])
    if !remote_ec2_helper.check_open_port('default', 22)
      raise Exception.new("Port 22 must be opened for security group 'default' to connect via SSH in target-region")
    end
    if @input_params[:source_ssh_username] == nil
      @input_params[:source_ssh_username] = "root"
    end
    if @input_params[:target_ssh_username] == nil
      @input_params[:target_ssh_username] = "root"
    end
    if @input_params[:description] == nil || !check_string_alnum(@input_params[:description])
      @input_params[:description] = "Created by CloudyScripts - #{self.class.name}" 
    end
  end

  # Load the initial state for the script.
  # Abstract method to be implemented by extending classes.
  def load_initial_state()
    CopySnapshotState.load_state(@input_params)
  end

  private

  # Here begins the state machine implementation
  class CopySnapshotState < ScriptExecutionState

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
  class InitialState < CopySnapshotState
    def enter()
      result = launch_instance(@context[:source_ami_id], @context[:source_key_name], "default")
      @context[:source_instance_id] = result.first
      @context[:source_dns_name] = result[1]
      @context[:source_availability_zone] = result[2]
      SourceInstanceLaunchedState.new(@context)
    end
  end

  # Source is started. Create a volume from the snapshot, attach and mount the volume
  class SourceInstanceLaunchedState < CopySnapshotState
    def enter()
      @context[:source_volume_id] = create_volume_from_snapshot(@context[:snapshot_id],
        @context[:source_availability_zone])
      device = "/dev/sdj"  #TODO: make device configurable
      mount_point = "/mnt/tmp_#{@context[:source_volume_id]}"
      attach_volume(@context[:source_volume_id], @context[:source_instance_id], device)
      connect(@context[:source_dns_name], @context[:source_ssh_username], nil, @context[:source_ssh_keydata])
      mount_fs(mount_point, device)
      # get partition label and filesystem type
      #@context[:label] = get_partition_label(mount_point)
      #@context[:fs_type] = get_partition_fs_type(mount_point)
      @context[:fs_type], @context[:label] = get_partition_fs_type_and_label(mount_point)
      disconnect()
      SourceVolumeReadyState.new(@context)
    end
  end

  # Source is ready. Now start instance in the target region
  class SourceVolumeReadyState < CopySnapshotState
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
  class TargetInstanceLaunchedState < CopySnapshotState
    def enter()
      local_region()
      ec2_helper = Ec2Helper.new(@context[:ec2_api_handler])
      volume_size = ec2_helper.snapshot_prop(@context[:snapshot_id], :volumeSize).to_i
      #
      remote_region()
      @context[:target_volume_id] = create_volume(@context[:target_availability_zone], volume_size)
      device = "/dev/sdj"  #TODO: make device configurable
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
  class TargetVolumeReadyState < CopySnapshotState
    def enter()
      post_message("upload key of target-instance to source-instance...")
      path_candidates = ["/#{@context[:source_ssh_username]}/.ssh/",
        "/home/#{@context[:source_ssh_username]}/.ssh/"]
      key_path = determine_file(@context[:source_dns_name], @context[:source_ssh_username], @context[:source_ssh_keydata], path_candidates)
      #upload_file(@context[:source_dns_name], "root", @context[:source_ssh_keydata],
      #  @context[:target_ssh_keyfile], "#{key_path}#{@context[:target_key_name]}.pem")
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
  class KeyInPlaceState < CopySnapshotState
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
  class DataCopiedState < CopySnapshotState
    def enter()
      remote_region()
      @context[:new_snapshot_id] = create_snapshot(@context[:target_volume_id], @context[:description]) 
      @context[:result][:snapshot_id] = @context[:new_snapshot_id]
      SnapshotCreatedState.new(@context)
    end
  end

  # Operation done. Now only cleanup is missing, i.e. shut down instances and
  # remote the volumes that were created. Start with cleaning the ressources
  # in the local region.
  class SnapshotCreatedState < CopySnapshotState
    def enter()
      local_region()
      shut_down_instance(@context[:source_instance_id])
      delete_volume(@context[:source_volume_id])
      SourceCleanedUpState.new(@context)
    end
  end

  # Cleanup the resources in the target region.
  class SourceCleanedUpState < CopySnapshotState
    def enter()
      remote_region()
      shut_down_instance(@context[:target_instance_id])
      delete_volume(@context[:target_volume_id])
      Done.new(@context)
    end
  end

end

#Cloudy_Script: copy snapshots between regions
#start up instance in source-region, create volume from snapshot, attach volume, and mount it
#start up instance in destination-region, create empty volume of same size, attache volume, and mount it
#copy the destination key to the source instance
#perform an rsynch
#sync -PHAXaz --rsh "ssh -i /home/${src_user}/.ssh/id_${dst_keypair}" --rsync-path "sudo rsync" ${src_dir}/ ${dst_user}@${dst_public_fqdn}:${dst_dir}/
#create a snapshot of the volume
#clean-up everything
