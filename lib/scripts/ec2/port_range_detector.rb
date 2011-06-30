require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
#require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"

# Checks for all security groups of a region if no port ranges are defined.
#

class PortRangeDetector < Ec2Script
  # Input parameters
  # * ec2_api_handler => object that allows to access the EC2 API
  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:ec2_api_handler] == nil
      raise Exception.new("no EC2 handler specified")
    end
  end

  def load_initial_state()
    PortRangeDetectorState.load_state(@input_params)
  end
  
  private

  # Here begins the state machine implementation
  class PortRangeDetectorState < ScriptExecutionState
    def self.load_state(context)
      state = context[:initial_state] == nil ? InitialState.new(context) : context[:initial_state]
      state
    end

  end

  # Nothing done yet. Retrieve all security groups
  class InitialState < PortRangeDetectorState
    def enter
      retrieve_security_groups()
      SecurityGroupsRetrieved.new(@context)
    end
  end

  # Security groups retrieved. Start analysing them.
  class SecurityGroupsRetrieved < PortRangeDetectorState
    def enter
      @context[:result][:affected_groups] = []
      @context[:security_groups]['securityGroupInfo']['item'].each() do |group_info|
        post_message("checking group '#{group_info['groupName']}'...")
        next if group_info['ipPermissions'] == nil || group_info['ipPermissions']['item'] == nil
        group_info['ipPermissions']['item'].each() do |permission_info|
          logger.debug("permission_info = #{permission_info.inspect}")
          next unless permission_info['groups'] == nil #ignore access rights to other groups          
          if permission_info['toPort'] != permission_info['fromPort']
            if permission_info['ipRanges']['item'][0]['cidrIp'] == "0.0.0.0/0"
              @context[:result][:affected_groups] << {:name => group_info['groupName'],
                :from => permission_info['fromPort'], :to => permission_info['toPort']}
              post_message("=> found port range #{permission_info['fromPort']}-#{permission_info['toPort']}")
            end
          end
        end
      end
      SecurityGroupsAnalysed.new(@context)
    end
  end

  # Security groups analysed. Generate output and done.
  class SecurityGroupsAnalysed < PortRangeDetectorState
    def enter
      Done.new(@context)
    end
  end


  # Script done.
  class Done < PortRangeDetectorState
    def done?
      true
    end
  end
  
end
