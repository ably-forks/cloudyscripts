require "help/script_execution_state"
require "scripts/ec2/ec2_script"

# Encrypts an EC2 Storage
class DmEncrypt < Ec2Script
  def initialize(input_params)
    super(input_params)
  end

  # Input parameters
  # aws_access_key => the Amazon AWS Access Key (see Your Account -> Security Credentials)
  # aws_secret_key => the Amazon AWS Secret Key
  # ip_address => IP Address of the machine to connect to
  # ssh_key_file => Path of the keyfile used to connect to the machine
  # device => Path of the device to encrypt
  # device_name => Name of the Device to encrypt
  # storage_path => Path on which the encrypted device is mounted
  # remote_command_handler => object that allows to connect via ssh and execute commands
  # ec2_api_handler => object that allows to access the EC2 API
  # password => password used for encryption
  #
  def initialize(input_params)
    super(input_params)
    @result = {:done => false}
  end

  # Executes the script.
  def start_script
    begin
      current_state = DmEncryptState.load_state(@input_params)
      end_state = current_state.start_state_machine()
      if end_state.failed?
        @result[:failed] = true
        @result[:failure_reason] = current_state.end_state.failure_reason
        @result[:end_state] = current_state.end_state
      else
        @result[:failed] = false
      end
    rescue Exception => e
      puts "exception during encryption: #{e}"
      puts e.backtrace.join("\n")
      err = e.to_s
      err += " (in #{current_state.end_state.to_s})" unless current_state.blank?
      @result[:failed] = true
      @result[:failure_reason] = err
      @result[:end_state] = current_state.end_state unless current_state.blank?
    ensure
      begin
      @input_params[:remote_command_handler].disconnect
      rescue Exception => e2
        puts "rescue disconnect: #{e2}"
      end
    end

    #
    @result[:done] = true
  end

  # Returns a hash with the following information:
  # :done => if execution is done
  #
  def get_execution_result
    @result
  end

  private

  # Here begins the state machine implementation

  class DmEncryptState < ScriptExecutionState

    def self.load_state(context)
      InitialState.new(context)
    end
  end

  # Starting state. Tries to connect via ssh.
  class InitialState < DmEncryptState
    def enter
      connect()
    end

    private

    def connect()
      puts "InitialState.connect"
      @context[:remote_command_handler].connect(@context[:ip_address], @context[:ssh_key_file])
      ConnectedState.new(@context)
    end
  end

  # Connected via SSH. Tries to install dm-encrypt.#TODO: depends on OS
  class ConnectedState < DmEncryptState
    def enter
      install_tools()
    end

    private
    def install_tools
      puts "ConnectedState.install_tools"
      if !tools_installed?
        @context[:remote_command_handler].install("dm-crypt") #TODO: constant somewhere? admin parameter?
      end
      if tools_installed?
        puts "system says that tools are installed"
        ToolInstalledState.new(@context)
      else
        FailedState.new(@context, "Installation of Tools failed", ConnectedState.new(@context))
      end
    end

    def tools_installed?
      if @context[:remote_command_handler].tools_installed?("dm-crypt")
        true
      else
        false
      end
    end
  end

  # Connected and Tools installed. Start encryption.
  class ToolInstalledState < DmEncryptState
    def enter
      create_encrypted_volume()
    end

    private
    def create_encrypted_volume
      puts "ToolInstalledState.create_encrypted_volume"
      #first check if the drive is not yet mounted by someone else
      if @context[:remote_command_handler].drive_mounted?(@context[:storage_path])
        if !@context[:remote_command_handler].drive_mounted_as?(calc_device_name(), @context[:storage_path])
          raise Exception.new("Drive is already used by another device")
        end
      end
      #
      @context[:remote_command_handler].encrypt_storage(@context[:device_name],
      @context[:password], @context[:device], @context[:storage_path])
      VolumeCreatedState.new(@context)
    end

    def calc_device_name
      dev = @context[:device_name].gsub(/[-]/,"--")
      "/dev/mapper/vg--#{dev}-lv--#{dev}"
    end

  end

  class VolumeCreatedState < DmEncryptState
    def enter
      mount_and_activate()
    end

    private
    def mount_and_activate
      puts "VolumeCreatedState.mount_and_activate"
      @context[:remote_command_handler].activate_encrypted_volume(@context[:device_name],@context[:storage_path])
      MountedAndActivatedState.new(@context)
    end
  end

  class MountedAndActivatedState < DmEncryptState
    def enter
      cleanup()
    end

    private
    def cleanup()
      puts "MountedAndActivatedState.cleanup"
      @context[:remote_command_handler].disconnect()
      DoneState.new(@context)
    end

  end

  class DoneState < DmEncryptState
    def done?
      true
    end
  end

end