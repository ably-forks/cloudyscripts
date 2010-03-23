require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
require "AWS"

# Script to Encrypt an EC2 Storage (aka Elastic Block Storage)
# 
class DmEncrypt < Ec2Script
  # dependencies: tools that need to be installed to make things work
  TOOLS = ["cryptsetup"]
  # the parameters for which
  CHECK = ["cryptsetup"]

  # Input parameters
  # * aws_access_key => the Amazon AWS Access Key (see Your Account -> Security Credentials)
  # * aws_secret_key => the Amazon AWS Secret Key
  # * ip_address => IP Address of the machine to connect to
  # * ssh_key_file => Path of the keyfile used to connect to the machine (optional, otherwise: ssh_key_data)
  # * ssh_key_data => Key information (optional, otherwise: ssh_key_file)
  # * device => Path of the device to encrypt
  # * device_name => Name of the Device to encrypt
  # * storage_path => Path on which the encrypted device is mounted
  # * paraphrase => paraphrase used for encryption
  # * remote_command_handler => object that allows to connect via ssh and execute commands (optional)
  # * ec2_api_handler => object that allows to access the EC2 API (optional)
  # * ec2_api_server => server to connect to (option, default is us-east-1.ec2.amazonaws.com)
  #

  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:ec2_api_server] == nil
      @input_params[:ec2_api_server] = "us-east-1.ec2.amazonaws.com"
    end
    if @input_params[:remote_command_handler] == nil
      @input_params[:remote_command_handler] = RemoteCommandHandler.new
    end
    if @input_params[:ec2_api_handler] == nil
      @input_params[:ec2_api_handler] = AWS::EC2::Base.new(:access_key_id => @input_params[:aws_access_key],
      :secret_access_key => @input_params[:aws_secret_key], :server => @input_params[:ec2_api_server])
    end
  end

  def load_initial_state()
    DmEncryptState.load_state(@input_params)
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
      connect(@context[:dns_name], @context[:ssh_keyfile], @context[:ssh_keydata])
      install_tools()
    end

    private

    def install_tools
      @context[:script].post_message("check if the system has the cryptset-package installed")
      @logger.debug "ConnectedState.install_tools"
      if !tools_installed?
        @context[:script].post_message("cryptset-package not installed. Going to install it...")
        TOOLS.each() {|tool|
          @context[:remote_command_handler].install(tool)
        }
      end
      if !@context[:remote_command_handler].remote_execute("modprobe dm_crypt")
        raise Exception.new("dm-crypt module missing")
      end
      if tools_installed?
        @context[:script].post_message("cryptset-package is available")
        @logger.debug "system says that tools are installed"
        ToolInstalledState.new(@context)
      else
        FailedState.new(@context, "Installation of Tools failed", ConnectedState.new(@context))
      end
    end

    def tools_installed?
      CHECK.each() {|tool|
        if !@context[:remote_command_handler].tools_installed?(tool)
          return false
        end
      }
      true
    end
  end

  # Connected and Tools installed. Start encryption.
  class ToolInstalledState < DmEncryptState
    def enter
      create_encrypted_volume()
    end

    private
    def create_encrypted_volume
      @context[:script].post_message("going to encrypt device #{@context[:device]} "+
        "named '#{@context[:device_name]}' and mount it as #{@context[:storage_path]}...")
      @logger.debug "ToolInstalledState.create_encrypted_volume"
      @context[:remote_command_handler].encrypt_storage(@context[:device_name],
      @context[:paraphrase], @context[:device], @context[:storage_path])
      @context[:script].post_message("device #{@context[:device]} is encrypted and mounted")
      MountedAndActivatedState.new(@context)
    end

    def calc_device_name
      dev = @context[:device_name].gsub(/[-]/,"--")
      "/dev/mapper/vg--#{dev}-lv--#{dev}"
    end

  end

  # The encrypted storages is mounted and activated. Cleanup and done.
  class MountedAndActivatedState < DmEncryptState
    def enter
      cleanup()
    end

    private
    def cleanup()
      @context[:script].post_message("disconnecting...")
      @logger.debug "MountedAndActivatedState.cleanup"
      @context[:remote_command_handler].disconnect()
      @context[:script].post_message("done")
      DoneState.new(@context)
    end

  end

  class DoneState < DmEncryptState
    def done?
      true
    end
  end

end