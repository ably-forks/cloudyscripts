require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
#require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"
#require 'pp'

# Checks for all security groups if sensible ports are opened for the wide
# public.
#

class VpcCriticalPortsAudit < Ec2Script
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
        #check only VPC SecurityGroups
        next if group_info['vpcId'].nil? || group_info['vpcId'].empty? 
        post_message("checking VPC SecurityGroup '#{group_info['groupName']}'...")
        vpc = @context[:ec2_api_handler].describe_vpcs(:vpc_id => group_info['vpcId'])
        vpc_ref = "" 
        vpc_item = vpc['vpcSet']['item'][0]
        if !vpc_item['name'].nil? && !vpc_item['name'].empty?
          vpc_ref = vpc_item['name']
        else
          #XXX: shold be the same as "group_info['vpcId']"
          vpc_ref = vpc_item['vpcId']
        end
        igw = @context[:ec2_api_handler].describe_internetgateways()
        igw_ref = ""
        found = false
        igw['internetGatewaySet']['item'].each {|igw_item|
          break if found == true
          igw_id = igw_item['internetGatewayId']
          igw_item['attachmentSet']['item'].each {|vpc_item|
            if vpc_item['vpcId'].eql?("#{group_info['vpcId']}")
              igw_ref = igw_id
              found = true
              break
            end
          }
        }
        next if group_info['ipPermissions'] == nil || group_info['ipPermissions']['item'] == nil
        group_info['ipPermissions']['item'].each() do |permission_info|
          logger.debug("permission_info = #{permission_info.inspect}")
          next unless permission_info['groups'] == nil #ignore access rights to other groups
          next unless permission_info['ipRanges']['item'][0]['cidrIp'] == "0.0.0.0/0"
          #now check if a critical port is within the port-range
          #XXX: allow to skip the 'critical port' options if nil
          if @context[:critical_ports] == nil || @context[:critical_ports].empty?
            port = nil
            if permission_info['fromPort'].to_i == permission_info['toPort'].to_i
              port = permission_info['fromPort'].to_i
              post_message("=> found unique port: #{port}")
            end
            @context[:result][:affected_groups] << {:name => group_info['groupName'],
                  :from =>  permission_info['fromPort'], :to => permission_info['toPort'], 
                  :concerned => port, :prot => permission_info['ipProtocol'], 
                  :vpc_ref => vpc_ref, :igw_ref => igw_ref}
            post_message("=> found at least one port publicly opened")
          else
            @context[:critical_ports].each() do |port|
              if permission_info['fromPort'].to_i <= port && permission_info['toPort'].to_i >= port
                @context[:result][:affected_groups] << {:name => group_info['groupName'],
                  :from => permission_info['fromPort'], :to => permission_info['toPort'], 
                  :concerned => port, :prot => permission_info['ipProtocol'], 
                  :vpc_ref => vpc_ref, :igw_ref => igw_ref}
                post_message("=> found publically accessible port range that contains "+
                    "critical port for group #{group_info['groupName']}: #{permission_info['fromPort']}-#{permission_info['toPort']}")
              end
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
