require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
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
  # * ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]
  # * ssh_key_files => Key information for the security group that starts the AMI
  # * snapshot_id => The ID of the snapshot to be downloaded
  # * wait_time (optional, default = 300) => time in sec during which the zipped snapshot is downloadable
  # * zip_file_dest (optional, default = '/var/www/html') => path of directory where the zipped volume is copied to
  # * zip_file_name (option, default = 'download') => name of the zip-file to download
  def initialize(input_params)
    super(input_params)
  end

  # Returns a hash with the following information:
  # :done => if execution is done
  #
  def get_execution_result
    @result
  end

  def start_script
    if @input_params[:temp_device_name] == nil
      @input_params[:temp_device_name] = "/dev/sdj"
    end
    if @input_params[:zip_file_dest] == nil
      @input_params[:zip_file_dest] = "/var/www/html/"
    end
    if @input_params[:zip_file_name] == nil
      @input_params[:zip_file_name] = "download"
    end
    if @input_params[:wait_time] == nil
      @input_params[:wait_time] = 300
    end
    begin
      @input_params[:script] = self
      # start state machine
      current_state = DownloadSnapshotState.load_state(@input_params)
      @state_change_listeners.each() {|listener|
        current_state.register_state_change_listener(listener)
      }
      end_state = current_state.start_state_machine()
      if end_state.failed?
        @result[:failed] = true
        @result[:failure_reason] = current_state.end_state.failure_reason
        @result[:end_state] = current_state.end_state
      else
        @result[:failed] = false
      end
    rescue Exception => e
      @logger.warn "exception during encryption: #{e}"
      @logger.warn e.backtrace.join("\n")
      err = e.to_s
      err += " (in #{current_state.end_state.to_s})" unless current_state == nil
      @result[:failed] = true
      @result[:failure_reason] = err
      @result[:end_state] = current_state.end_state unless current_state == nil
    ensure
      begin
      @input_params[:remote_command_handler].disconnect
      rescue Exception => e2
      end
    end
    #
    @result[:done] = true
  end

  private

  # Here begins the state machine implementation
  class DownloadSnapshotState < ScriptExecutionState

    def self.load_state(context)
      InitialState.new(context)
    end
  end

  #Connected.
  # Start state. First thing to do is to launch the instance.
  class InitialState < DownloadSnapshotState
    def enter
      launch_instance()
      InstanceLaunchedState.new(context)
    end
  end

  # Instance Launched. Create a volume based on the snapshot.
  class InstanceLaunchedState < DownloadSnapshotState
    def enter
      create_volume_from_snapshot()
      VolumeCreated.new(@context)
    end

  end

  # Volume created. Attach it.
  class VolumeCreated < DownloadSnapshotState
    def enter
      attach_volume()
      VolumeAttached.new(@context)
    end
  end

  # Volume attached. Create a file-system and mount it.
  class VolumeAttached < DownloadSnapshotState
    def enter
      create_fs()
      FileSystemCreated.new(@context)
    end
  end

  # File system created. Mount it.
  class FileSystemCreated < DownloadSnapshotState
    def enter
      connect()
      mount_fs()
      FileSystemMounted.new(@context)
    end

  end

  # File System mounted. Zip the complete directory on the EBS.
  class FileSystemMounted < DownloadSnapshotState
    def enter
      zip_volume()
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
      shut_down_instance()
      InstanceShutDown.new(@context)
    end
    
  end

  # Instance is shut down. Delete the volume created.
  class InstanceShutDown < DownloadSnapshotState
    def enter
      delete_volume()
      Done.new(@context)
    end
  end

end
