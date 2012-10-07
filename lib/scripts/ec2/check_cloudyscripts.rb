require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"

# Goal: check internal piece of CloudyScripts without launching the full scripts
#

class CheckCloudyScripts < Ec2Script
  
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
    CheckCloudyScriptsState.load_state(@input_params)
  end

  private

  # Here begins the state machine implementation
  class CheckCloudyScriptsState < ScriptExecutionState

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
  class InitialState < CheckCloudyScriptsState
    def enter()
      post_message("INFO: Entering InitialState...")

      #@context[:source_instance_id], @context[:source_dns_name], @context[:source_availability_zone], 
      #  @context[:kernel_id], @context[:ramdisk_id], @context[:architecture], @context[:root_device_name] =
      #  launch_instance(@context[:ami_id], @context[:source_key_name], "default")
      start_instance(@context[:source_instance_id])
      res = describe_instance(@context[:source_instance_id])
      puts "DEBUG: instance: #{res.inspect}"
      #@context[:source_instance_id] = "i-0a663643" 
      @context[:source_dns_name] = res[1]
      @context[:source_availability_zone] = res[2]
      @context[:kernel_id] = res[3]
      @context[:ramdisk_id] = res[4]
      @context[:architecture] = res[5]
      @context[:root_device_name] = res[6]

      ec2_helper = Ec2Helper.new(@context[:ec2_api_handler])
      puts "DEBUG: get_attached returns: #{ec2_helper.get_attached_volumes(@context[:source_instance_id]).inspect}"
      @context[:ebs_volume_id] = ec2_helper.get_attached_volumes(@context[:source_instance_id])[0]['volumeId']#TODO: what when more root devices?

      CSTestingState.new(@context)
    end
  end

  # Snapshot is created from the AMI. Create a volume from the snapshot, attach and mount the volume as second device.
  class CSTestingState < CheckCloudyScriptsState
    def enter()
      post_message("INFO: Entering CSTestingState...")

      #@context[:source_volume_id] = create_volume_from_snapshot(@context[:snapshot_id],
      #  @context[:source_availability_zone])
      @context[:source_volume_id] = "vol-6eb34b06" 

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
      puts "DEBUG: AWS info: #{aws_root_device}, #{aws_letter}"
      puts "DEBUG: OS info: #{root_device_name}, #{os_letter}"
      if !aws_letter.eql?(os_letter)
        post_message("Detected specific kernel with shift between AWS and Kernel OS for device naming")
        puts "Detected specific kernel with shift between AWS and Kernel OS for device naming (#{aws_root_device} vs #{root_device_name})"
      end
      while !aws_letter.eql?(os_letter)
        aws_letter.succ!
        aws_device_letter.succ!
      end
      device = "/dev/sd#{aws_device_letter}" 
      post_message("Using AWS name '#{@context[:temp_device_name]}' and OS name '#{device}'")
      puts "Using AWS name '#{@context[:temp_device_name]}' and OS name '#{device}'"
      mount_fs(mount_point, device)
      # get root partition label and filesystem type
      #@context[:label] = get_root_partition_label()
      #@context[:fs_type] = get_root_partition_fs_type()
      @context[:fs_type], @context[:label] = get_root_partition_fs_type_and_label()
      disconnect()

      Done.new()
    end
  end

end
