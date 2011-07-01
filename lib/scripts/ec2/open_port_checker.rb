require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
#require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"

# Identifies all server instances with their ports open and checks if
# there are instances where no service runs on that port. Port ranges are
# ignored.
#

class OpenPortChecker < Ec2Script
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
    OpenPortCheckerState.load_state(@input_params)
  end

  private

  # Here begins the state machine implementation
  class OpenPortCheckerState < ScriptExecutionState
    def self.load_state(context)
      state = context[:initial_state] == nil ? InitialState.new(context) : context[:initial_state]
      state
    end

  end

  # Nothing done yet. Retrieve all security groups
  class InitialState < OpenPortCheckerState
    def enter
      retrieve_instances()
      InstancesRetrievedState.new(@context)
    end
  end

  # Got all instances. If there are some, check security groups
  class InstancesRetrievedState < OpenPortCheckerState
    def enter
      if @context[:ec2_instances].size == 0
        Done.new(@context)
      else
        retrieve_security_groups()
        SecurityGroupsRetrievedState.new(@context)
      end
    end
  end

  # Got all instances. If there are some, check security groups
  class SecurityGroupsRetrievedState < OpenPortCheckerState
    def enter
      @context[:result][:port_checks] = []
      ec2_helper = Ec2Helper.new(@context[:ec2_api_handler])
      @context[:ec2_instances]['reservationSet']['item'].each() do |instance_info|
        instance_id = ec2_helper.get_instance_id(instance_info)
        @logger.debug("instance_info = #{instance_info.inspect}")
        instance_ip = ec2_helper.instance_prop(instance_id, 'dnsName', @context[:ec2_instances])
        instance_state = ec2_helper.instance_prop(instance_id, 'instanceState', @context[:ec2_instances])['name']
        next unless instance_state == "running"
        sec_groups = ec2_helper.lookup_security_group_names(instance_info)
        @logger.debug("group lookup for #{instance_id} => #{sec_groups.inspect}")
        sec_groups.each() do |group_name|
          port_infos = ec2_helper.lookup_open_ports(group_name, @context[:security_groups])
          @logger.debug("port_infos for group #{group_name} #{port_infos.inspect}")
          port_infos.each() do |port_info|
            result = false
            begin
              result = @context[:remote_command_handler].is_port_open?(instance_ip, port_info[:port])
              post_message("check port #{port_info[:port]} for instance #{instance_id} (on #{instance_ip}) #{result ? "successful" : "failed"}")
            rescue Exception => e
              @logger.warn("exception during executing port check: #{e}")
            end
            @context[:result][:port_checks] << {:instance => instance_id, :protocol => port_info[:protocol],
              :port => port_info[:port], :success => result
            }
          end
        end
      end
      AnalysisDone.new(@context)
    end
  end

  # Nothing done yet. Retrieve all security groups
  class AnalysisDone < OpenPortCheckerState
    def enter
      Done.new(@context)
    end
  end

  # Script done.
  class Done < OpenPortCheckerState
    def done?
      true
    end
  end

end
