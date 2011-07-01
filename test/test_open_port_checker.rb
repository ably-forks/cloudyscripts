require "mock/mocked_ec2_api"
require "mock/mocked_state_change_listener"
require "mock/mocked_remote_command_handler"

require "scripts/ec2/open_port_checker"

require 'test/unit'

class TestOpenPortChecker < Test::Unit::TestCase
  def test_execution
    ec2_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "web-service")
    options = {:group_name => "web-service", :ip_protocol => "tcp", :from_port => 80,
        :to_port => 80, :cidr_ip => "0.0.0.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    options = {:group_name => "thousand", :ip_protocol => "tcp", :from_port => 443,
        :to_port => 443, :cidr_ip => "0.0.0.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    ec2_api.create_dummy_instance("i-11111", "ami-11111",
      "running", "i1.ec2.amazonaws.com",
      "i1.ec2.amazonaws.com", "key1", ["web-service"])
    ec2_api.create_dummy_instance("i-22222", "ami-22222",
      "running", "i2.ec2.amazonaws.com",
      "i2.ec2.amazonaws.com", "key2", ["thousand"])
    #
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    params = {
      :ec2_api_handler => ec2_api,
      :remote_command_handler => MockedRemoteCommandHandler.new,
      :logger => logger,
    }
    script = OpenPortChecker.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    puts "results = #{script.get_execution_result().inspect}"
    assert script.get_execution_result[:done]
    assert !script.get_execution_result[:failed]
    port_checks = [{:port=>22, :instance=>"i-11111", :success=>false, :protocol=>"tcp"}, {:port=>80, :instance=>"i-11111", :success=>true, :protocol=>"tcp"}, {:port=>22, :instance=>"i-22222", :success=>false, :protocol=>"tcp"}]
    assert_equal port_checks, script.get_execution_result[:port_checks]
    puts "done in #{endtime-starttime}s"
  end

end
