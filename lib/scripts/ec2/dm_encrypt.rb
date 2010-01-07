require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/dm_crypt_helper"
require "AWS"

# Script to Encrypt an EC2 Storage (aka Elastic Block Storage)
# 
class DmEncrypt < Ec2Script
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
    @result = {:done => false}
  end

  # Executes the script.
  def start_script
    begin
      # optional parameters and initialization
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
      # start state machine
      current_state = DmEncryptState.load_state(@input_params)
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
      @logger.info e.backtrace.join("\n")
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
      @logger.debug "InitialState.connect"
      if @context[:ssh_key_file] != nil
        @context[:remote_command_handler].connect_with_keyfile(@context[:ip_address], @context[:ssh_key_file])
      elsif @context[:ssh_key_data] != nil
        @context[:remote_command_handler].connect(@context[:ip_address], "root", @context[:ssh_key_data])
      else
        raise Exception.new("no key information specified")
      end
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
      @logger.debug "ConnectedState.install_tools"
      if !tools_installed?
        @context[:remote_command_handler].install("dm-crypt") #TODO: constant somewhere? admin parameter?
      end
      if tools_installed?
        @logger.debug "system says that tools are installed"
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
      @logger.debug "ToolInstalledState.create_encrypted_volume"
      #first check if the drive is not yet mounted by someone else
      if @context[:remote_command_handler].drive_mounted?(@context[:storage_path])
        if !@context[:remote_command_handler].drive_mounted_as?(calc_device_name(), @context[:storage_path])
          raise Exception.new("Drive is already used by another device")
        end
      end
      #
      @context[:remote_command_handler].encrypt_storage(@context[:device_name],
      @context[:paraphrase], @context[:device], @context[:storage_path])
      VolumeCreatedState.new(@context)
    end

    def calc_device_name
      dev = @context[:device_name].gsub(/[-]/,"--")
      "/dev/mapper/vg--#{dev}-lv--#{dev}"
    end

  end

  # The encrypted Volume is created. Going to mount it.
  class VolumeCreatedState < DmEncryptState
    def enter
      mount_and_activate()
    end

    private
    def mount_and_activate
      @logger.debug "VolumeCreatedState.mount_and_activate"
      @context[:remote_command_handler].activate_encrypted_volume(@context[:device_name],@context[:storage_path])
      MountedAndActivatedState.new(@context)
    end
  end

  # The encrypted storages is mounted. Cleanup and done.
  class MountedAndActivatedState < DmEncryptState
    def enter
      cleanup()
    end

    private
    def cleanup()
      @logger.debug "MountedAndActivatedState.cleanup"
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