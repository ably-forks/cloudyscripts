require "mock/mocked_v_cloud_api"
require "mock/mocked_state_change_listener"
require "mock/mocked_remote_command_handler"

require "scripts/vCloud/open_port_checker_vm"

require 'test/unit'

class TestVCloudOpenPortChecker < Test::Unit::TestCase
  def test_execution
    vcloud_api = MockedVCloudApi.new(nil,nil,nil)
    vcloud_api._create_internet_service("1.2.3.4", 443, 500000)
    vcloud_api._create_internet_service("11.22.33.44", 4444, 600000)
    rch = MockedRemoteCommandHandler.new
    rch.open_ports = [4444]
    #
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    params = {
      :vcloud_api_handler => vcloud_api,
      :remote_command_handler => rch,
      :logger => logger,
    }
    script = OpenPortCheckerVm.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    puts "results = #{script.get_execution_result().inspect}"
    assert script.get_execution_result[:done]
    assert !script.get_execution_result[:failed]
    port_checks = [{:port=>443, :ip =>"1.2.3.4", :success=>false, :id => "5000000"},
      {:port=>4444, :ip=>"11.22.33.44", :success=>true, :id => "6000000"}]
    assert_equal port_checks, script.get_execution_result[:port_checks]
    puts "done in #{endtime-starttime}s"
  end

end
