require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
#require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"

# Checks for all security groups if sensible ports are opened for the wide
# public.
#

class CriticalPortsAudit < Ec2Script
  # Input parameters
  # * ec2_api_handler => object that allows to access the EC2 API
  # * :critical_ports => arrays of ports to be checked
  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:ec2_api_handler] == nil
      raise Exception.new("no EC2 handler specified")
    end
    #if @input_params[:critical_ports] == nil
    #  raise Exception.new("no ports specified")
    #end
  end

  def load_initial_state()
    CriticalPortsAuditState.load_state(@input_params)
  end
  
  private

  # Here begins the state machine implementation
  class CriticalPortsAuditState < ScriptExecutionState
    def self.load_state(context)
      state = context[:initial_state] == nil ? RetrievingSecurityGroups.new(context) : context[:initial_state]
      state
    end
  end

  # Nothing done yet. Retrieve all security groups
  class RetrievingSecurityGroups < CriticalPortsAuditState
    def enter
      retrieve_security_groups()
      CheckingSensiblePorts.new(@context)
    end
  end

  # Security groups retrieved. Start analysing them.
  class CheckingSensiblePorts< CriticalPortsAuditState
    def enter
      @context[:result][:affected_groups] = []
      @context[:security_groups]['securityGroupInfo']['item'].each() do |group_info|
        next if !group_info['vpcId'].nil? && !group_info['vpcId'].empty?
        post_message("checking group '#{group_info['groupName']}'...")
        next if group_info['ipPermissions'] == nil || group_info['ipPermissions']['item'] == nil
        group_info['ipPermissions']['item'].each() do |permission_info|
          logger.debug("permission_info = #{permission_info.inspect}")
          next unless permission_info['groups'] == nil #ignore access rights to other groups
          next unless permission_info['ipRanges']['item'][0]['cidrIp'] == "0.0.0.0/0"
          #now check if a critical port is within the port-range
          @context[:critical_ports].each() do |port|
            if permission_info['fromPort'].to_i <= port && permission_info['toPort'].to_i >= port
              @context[:result][:affected_groups] << {:name => group_info['groupName'],
                :from => permission_info['fromPort'], :to => permission_info['toPort'], 
                :concerned => port, :prot => permission_info['ipProtocol']}
              post_message("=> found publically accessible port range that contains "+
                  "critical port for group #{group_info['groupName']}: #{permission_info['fromPort']}-#{permission_info['toPort']}")
            end
          end
        end
      end
      Done.new(@context)
    end
  end

  # Script done.
  class Done < CriticalPortsAuditState
    def done?
      true
    end
  end
  
end
