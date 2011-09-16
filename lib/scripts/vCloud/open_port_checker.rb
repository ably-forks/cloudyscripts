require "help/script_execution_state"
require "help/remote_command_handler"
require "scripts/vcloud/v_cloud_script"

# Identifies all open internet services and checks if
# there are actually used by a service.
#

class OpenPortChecker < VCloudScript
  # Input parameters
  # * vcloud_api_handler => object that allows to access the vCloud service
  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:vcloud_api_handler] == nil
      raise Exception.new("no vCloud handler specified")
    end
  end

  def load_initial_state()
    OpenPortCheckerState.load_state(@input_params)
  end

  private

  # Here begins the state machine implementation
  class OpenPortCheckerState < ScriptExecutionState
    def self.load_state(context)
      state = context[:initial_state] == nil ? RetrievingInternetServices.new(context) : context[:initial_state]
      state
    end

  end

  # Nothing done yet. Retrieve all internet services.
  class RetrievingInternetServices < OpenPortCheckerState
    def enter
      retrieve_ip_services()
      CheckingInternetServices.new(@context)
    end
  end

  # Got all internet services. Go through them and check the ports.
  class CheckingInternetServices < OpenPortCheckerState
    def enter
      @context[:result][:port_checks] = []
      @context[:vcloud_internet_services].each() do |is|
        port = is[:port]
        ip = is[:ip]
        begin
          result = @context[:remote_command_handler].is_port_open?(ip, port)
          post_message("check port #{port} on IP #{ip} => #{result ? "successful" : "failed"}")
        rescue Exception => e
          @logger.warn("exception during executing port check: #{e}")
        end
        @context[:result][:port_checks] << {:ip => ip,
          :port => port, :success => result
        }
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
