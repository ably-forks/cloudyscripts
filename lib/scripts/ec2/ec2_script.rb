# Base class for any script on EC2.
class Ec2Script
  # Initialization. Common Input parameters:
  # * aws_access_key => the Amazon AWS Access Key (see Your Account -> Security Credentials)
  # * aws_secret_key => the Amazon AWS Secret Key
  # * ec2_api_server => the API Server to connect to (optional, default is us-east-1 (=> <ec2_api_server>.ec2.amazonaws.com)
  # * logger => allows to pass a ruby logger object used for logging (optional, default is a stdout logger with level WARN)
  # Scripts may add specific key/value pairs.
  def initialize(input_params)
    @input_params = input_params
    @state_change_listeners = []
    @progress_message_listeners = []
    if input_params[:logger] == nil
      @logger = Logger.new(STDOUT)
      @logger .level = Logger::WARN
      input_params[:logger] = @logger
    end
    @result = {:done => false, :failed => false}
    @input_params[:result] = @result
  end

  def register_state_change_listener(listener)
    @state_change_listeners << listener
  end

  def register_progress_message_listener(listener)
    @progress_message_listeners << listener
  end

  def start_script
    raise Exception.new("must be implemented")
  end

  # Return a hash of results. Common values are:
  # * :done => is true when the script has terminated, otherwise false
  # * :failed => is false when the script succeeded
  # * :failure_reason => returns a failure reason (string)
  # * :end_state => returns the state, in which the script terminated (#Help::ScriptExecutionState)
  # Scripts may add specific key/value pairs.
  # * 
  def get_execution_result
    raise Exception.new("must be implemented")
  end

  def post_message(message, level = Logger::DEBUG)
    @progress_message_listeners.each() {|listener|
      listener.new_message(message, level)
    }
  end
  
end

