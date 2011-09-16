# Base class for any script for vCloud.
class VCloudScript
  # Initialization. Common Input parameters:
  # * vcloud_api_handler => used to connect to the API (needs user/password/api-url)
  # * logger => allows to pass a ruby logger object used for logging (optional, default is a stdout logger with level WARN)
  # Scripts may add specific key/value pairs.
  def initialize(input_params)
    @input_params = input_params
    @state_change_listeners = []
    @progress_message_listeners = []
    if input_params[:logger] == nil
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::WARN
      input_params[:logger] = @logger
    else
      @logger = input_params[:logger]
    end
    @result = {:done => false, :failed => false}
    @input_params[:result] = @result
    @input_params.each() do |param_key, param_value|
      if [:logger, :vcloud_api_handler, :target_ec2_handler, :remote_command_handler,
        :source_ssh_keydata, :target_ssh_keydata, :ssh_keydata
        ].include?(param_key.to_s.to_sym)
        @logger.debug("INPUT PARAM #{param_key} is set [but not logged]")
      else
        @logger.debug("INPUT PARAM #{param_key} = #{param_value.inspect}")
      end
    end
  end

  def register_state_change_listener(listener)
    @state_change_listeners << listener
  end

  def register_progress_message_listener(listener)
    @progress_message_listeners << listener
  end

  # Check input parameters (in @input_parameters object variable)
  # and set default values.
  # Abstract method to be implemented by extending classes.
  def check_input_parameters()
    raise Exception.new("check_input_parameters must be implemented")
  end

  # Load the initial state for the script.
  # Abstract method to be implemented by extending classes.
  def load_initial_state()
    raise Exception.new("load_initial_state must be implemented")
  end

  # Executes the script.
  def start_script()
    # optional parameters and initialization
    check_input_parameters()
    @input_params[:script] = self
    begin
      current_state = load_initial_state()
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
      @logger.warn "exception during execution: #{e}"
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


  # Return a hash of results. Common values are:
  # * :done => is true when the script has terminated, otherwise false
  # * :failed => is false when the script succeeded
  # * :failure_reason => returns a failure reason (string)
  # * :end_state => returns the state, in which the script terminated (#Help::ScriptExecutionState)
  # Scripts may add specific key/value pairs.
  # * 
  # Returns a hash with the following information:
  # :done => if execution is done
  #
  def get_execution_result
    @result
  end

  def post_message(message, level = Logger::DEBUG)
    @progress_message_listeners.each() {|listener|
      listener.new_message(message, level)
    }
  end
  
end

