# Base class for any script on EC2.
class Ec2Script
  # Initialization. Common Input parameters:
  # * aws_access_key => the Amazon AWS Access Key (see Your Account -> Security Credentials)
  # * aws_secret_key => the Amazon AWS Secret Key
  # * ec2_api_server => the API Server to connect to (optional, default is us-east-1 (=> <ec2_api_server>.ec2.amazonaws.com)
  # Scripts may add specific key/value pairs.
  def initialize(input_params)
    @input_params = input_params
    @state_change_listeners = []
  end

  def register_state_change_listener(listener)
    @state_change_listeners << listener
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

end

