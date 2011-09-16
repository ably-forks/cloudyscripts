require "mock/mocked_ec2_api"
require "mock/mocked_state_change_listener"

require "scripts/ec2/port_range_detector"

require 'test/unit'

class TestPortRangeDetector < Test::Unit::TestCase
  def test_execution
    ec2_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "Hella")
    options = {:group_name => "Hella", :ip_protocol => "tcp", :from_port => 80,
        :to_port => 3000, :cidr_ip => "10.0.0.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    ec2_api.create_security_group(:group_name => "Exceeded")
    options = {:group_name => "Exceeded", :ip_protocol => "tcp", :from_port => 1000,
        :to_port => 2000, :cidr_ip => "0.0.0.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    options = {:group_name => "Exceeded", :ip_protocol => "tcp", :from_port => 2500,
        :to_port => 3000, :cidr_ip => "0.0.0.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    puts "describe security groups: #{ec2_api.describe_security_groups().inspect}"
    params = {
      :ec2_api_handler => ec2_api,
      :logger => logger,
    }
    script = PortRangeDetector.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    puts "results = #{script.get_execution_result().inspect}"
    assert script.get_execution_result[:done]
    assert !script.get_execution_result[:failed]
    assert_equal 2, script.get_execution_result[:affected_groups].size
    puts "done in #{endtime-starttime}s"
  end

end
