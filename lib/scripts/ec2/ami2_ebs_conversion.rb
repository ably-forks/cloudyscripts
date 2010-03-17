require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
#require "help/dm_crypt_helper"
require "AWS"

class AWS::EC2::Base
  def register_image_updated(options)
    params = {}
    params["Name"] = options[:name].to_s
    params["BlockDeviceMapping.1.Ebs.SnapshotId"] = options[:snapshot_id].to_s
    params["BlockDeviceMapping.1.DeviceName"] = options[:root_device_name].to_s
    params["Description"] = options[:description].to_s
    params["KernelId"] = options[:kernel_id].to_s
    params["RamdiskId"] = options[:ramdisk_id].to_s
    params["Architecture"] = options[:architecture].to_s
    params["RootDeviceName"] = options[:root_device_name].to_s
    return response_generator(:action => "RegisterImage", :params => params)
  end
end

# Creates a bootable EBS storage from an existing AMI.
#

class Ami2EbsConversion < Ec2Script
  # Input parameters
  # * aws_access_key => the Amazon AWS Access Key (see Your Account -> Security Credentials)
  # * aws_secret_key => the Amazon AWS Secret Key
  # * ami_id => the ID of the AMI to be converted
  # * security_group_name => name of the security group to start
  # * ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]
  # * ssh_key_files => Key information for the security group that starts the AMI
  # * remote_command_handler => object that allows to connect via ssh and execute commands (optional)
  # * ec2_api_handler => object that allows to access the EC2 API (optional)
  # * ec2_api_server => server to connect to (option, default is us-east-1.ec2.amazonaws.com)
  # * name => the name of the AMI to be created
  # * description => description on AMI to be created (optional)
  # * temp_device_name => [default /dev/sdj] device name used to attach the temporary storage; change this only if there's already a volume attacged as /dev/sdj (optional, default is /dev/sdj)
  # * root_device_name"=> [default /dev/sda1] device name used for the root device (optional)
  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:name] == nil
      @input_params[:name] = "Boot EBS (for AMI #{@input_params[:ami_id]}) at #{Time.now.strftime('%d/%m/%Y %H.%M.%S')}"
    else
    end
    if @input_params[:description] == nil
      @input_params[:description] = @input_params[:name]
    end
    if @input_params[:temp_device_name] == nil
      @input_params[:temp_device_name] = "/dev/sdj"
    end
    if @input_params[:root_device_name] == nil
      @input_params[:root_device_name] = "/dev/sda1"
    end
  end

  def load_initial_state()
    Ami2EbsConversionState.load_state(@input_params)
  end
  
  private

  # Here begins the state machine implementation
  class Ami2EbsConversionState < ScriptExecutionState
    def self.load_state(context)
      state = context[:initial_state] == nil ? InitialState.new(context) : context[:initial_state]
      state
    end

  end

  # Nothing done yet. Start by instantiating an AMI (in the right zone?)
  # which serves to create 
  class InitialState < Ami2EbsConversionState
    def enter
      launch_instance()
      AmiStarted.new(@context)
    end
  end

  # Ami started. Create a storage
  class AmiStarted < Ami2EbsConversionState
    def enter
      create_volume()
      StorageCreated.new(@context)
    end
  end

  # Storage created. Attach it.
  class StorageCreated < Ami2EbsConversionState
    def enter
      attach_volume()
      StorageAttached.new(@context)
    end
  end

  # Storage attached. Create a file-system and moun it
  class StorageAttached < Ami2EbsConversionState
    def enter
      connect()
      create_fs()
      FileSystemCreated.new(@context)
    end
  end

  # File system created. Mount it.
  class FileSystemCreated < Ami2EbsConversionState
    def enter
      mount_fs()
      FileSystemMounted.new(@context)
    end
  end

  # File system created and mounted. Copy the root partition.
  class FileSystemMounted < Ami2EbsConversionState
    def enter
      copy()
      CopyDone.new(@context)
    end
  end
  
  # Copy operation done. Unmount volume.
  class CopyDone < Ami2EbsConversionState
    def enter
      unmount_fs()
      VolumeUnmounted.new(@context)
    end
  end

  # Volume unmounted. Detach it.
  class VolumeUnmounted < Ami2EbsConversionState
    def enter
      detach_volume()
      VolumeDetached.new(@context)
    end
  end

  # VolumeDetached. Create snaphot
  class VolumeDetached < Ami2EbsConversionState
    def enter
      create_snapshot()
      SnapshotCreated.new(@context)
    end
  end

  # Snapshot created. Delete volume.
  class SnapshotCreated < Ami2EbsConversionState
    def enter
      delete_volume()
      VolumeDeleted.new(@context)
    end
  end

  # Volume deleted. Register snapshot.
  class VolumeDeleted < Ami2EbsConversionState
    def enter
      register_snapshot()
      SnapshotRegistered.new(@context)
    end
  end

  # Snapshot registered. Shutdown instance.
  class SnapshotRegistered < Ami2EbsConversionState
    def enter
      shut_down_instance()
      Done.new(@context)      
    end
  end

  # Instance shutdown. Done.
  class Done < Ami2EbsConversionState
    def done?
      true
    end
  end
  
end
