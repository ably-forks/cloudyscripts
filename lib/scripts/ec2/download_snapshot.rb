require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"

# Script to download a specific snapshot as ZIP
# * create a specific instance (with Apache Server),
# * create a volume based on the snapshot
# * attach the volume
# * create a XSF-file-system
# * freeze the file-system
# * zip the file-system and copy it to the apache folder
# * wait 5 minutes (now the zip-file can be downloaded)
#   * alternatively: copy it to S3 and make it downloadable
#   * alternatively: copy it to an FTP server
# 
class DownloadSnapshot < Ec2Script
  # context information needed
  # * the EC2 credentials (see #Ec2Script)
  # * ami_id: the ID of the AMI to be started to perform the operations and to run the web-server for download
  # * security_group_name => name of the security group used to start the AMI (should open ports for SSH and HTTP)
  # * key_name => Name of the key to be used to access the instance providing the download
  # * ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]
  # * ssh_key_files => Key information for the security group that starts the AMI
  # * snapshot_id => The ID of the snapshot to be downloaded
  # * wait_time (optional, default = 300) => time in sec during which the zipped snapshot is downloadable
  # * zip_file_dest (optional, default = '/var/www/html') => path of directory where the zipped volume is copied to
  # * zip_file_name (option, default = 'download') => name of the zip-file to download
  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:source_device] == nil
      @input_params[:source_device] = "/dev/sdj1"
    end
    if @input_params[:dest_device] == nil
      @input_params[:dest_device] = "/dev/sdj2"
    end
    if @input_params[:zip_file_dest] == nil
      @input_params[:zip_file_dest] = "/var/www/html"
    end
    if @input_params[:zip_file_name] == nil
      @input_params[:zip_file_name] = "download"
    end
    if @input_params[:wait_time] == nil
      @input_params[:wait_time] = 300
    end
  end

  # Load the initial state for the script.
  # Abstract method to be implemented by extending classes.
  def load_initial_state()
    DownloadSnapshotState.load_state(@input_params)
  end

  private

  # Here begins the state machine implementation
  class DownloadSnapshotState < ScriptExecutionState

    def self.load_state(context)
      InitialState.new(context)
    end
  end

  # Start state. First thing to do is to launch the instance.
  class InitialState < DownloadSnapshotState
    def enter
      result = launch_instance(@context[:ami_id], @context[:key_name], @context[:security_group_name])
      @context[:instance_id] = result.first
      @context[:dns_name] = result[1]
      @context[:availability_zone] = result[2]
      InstanceLaunchedState.new(context)
    end
  end

  # Instance Launched. Create a volume based on the snapshot.
  class InstanceLaunchedState < DownloadSnapshotState
    def enter
      @context[:source_volume_id] = create_volume_from_snapshot(@context[:snapshot_id], @context[:availability_zone])
      ec2_helper = Ec2Helper.new(@context[:ec2_api_handler])
      size = ec2_helper.volume_prop(@context[:source_volume_id], :size).to_i
      puts "retrieved volume size of #{size}"
      @context[:dest_volume_id] = create_volume(@context[:availability_zone], size)
      VolumesCreated.new(@context)
    end

  end

  # Volumes created. Attach it.
  class VolumesCreated < DownloadSnapshotState
    def enter
      @context[:script].post_message("Going to create two volumes. One with the snapshot data, one to store the zipped data for download.")
      attach_volume(@context[:source_volume_id], @context[:instance_id], @context[:source_device])
      attach_volume(@context[:dest_volume_id], @context[:instance_id], @context[:dest_device])
      VolumesAttached.new(@context)
    end
  end

  # Volumes attached. Create a file-system for the destination one, and mount both.
  class VolumesAttached < DownloadSnapshotState
    def enter
      @context[:script].post_message("Going to prepare the two volumes for the zip-operation.")
      @context[:result][:os] =
        connect(@context[:dns_name], @context[:ssh_keyfile], @context[:ssh_keydata])
      source_dir = "/mnt/tmp_#{@context[:source_volume_id]}"
      dest_dir = @context[:zip_file_dest]
      create_fs(@context[:dns_name], @context[:dest_device])
      mount_fs(source_dir, @context[:source_device])
      mount_fs(dest_dir, @context[:dest_device])
      FileSystemsReady.new(@context)
    end
  end

  # File System mounted. Zip the complete directory on the EBS.
  class FileSystemsReady < DownloadSnapshotState
    def enter
      mount_point = "/mnt/tmp_#{@context[:source_volume_id]}"
      zip_volume(mount_point, @context[:zip_file_dest], @context[:zip_file_name])
      VolumeZippedAndDownloadableState.new(@context)
    end

  end

  # Volume is zipped and downloadable. Wait 5 minutes.
  class VolumeZippedAndDownloadableState < DownloadSnapshotState
    def enter
      wait_some_time()
    end

    def get_link
      "http://#{@context[:dns_name]}/#{@context[:zip_file_name]}.zip"
    end

    private
    
    def wait_some_time
      @context[:script].post_message("The snapshot can be downloaded during #{@context[:wait_time]} seconds from link: #{get_link()}")
      sleep(@context[:wait_time])
      DownloadStoppedState.new(@context)
    end
  end

  # Snapshot can no longer be downloaded. Shut down the instance.
  class DownloadStoppedState < DownloadSnapshotState
    def enter
      shut_down_instance(@context[:instance_id])
      InstanceShutDown.new(@context)
    end
    
  end

  # Instance is shut down. Delete the volume created.
  class InstanceShutDown < DownloadSnapshotState
    def enter
      delete_volume(@context[:source_volume_id])
      delete_volume(@context[:dest_volume_id])
      Done.new(@context)
    end
  end

end
