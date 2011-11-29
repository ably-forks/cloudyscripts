require "mock/mocked_ec2_api"
require "mock/mocked_state_change_listener"

require "scripts/ec2/vpc_critical_ports_audit"

require 'test/unit'

class TestVpcCriticalPortsAudit < Test::Unit::TestCase
  def test_execution
    ec2_api = MockedEc2Api.new
    ec2_api.create_vpc(:vpc_id => "vpc-12345678", :cidr_blk => "10.0.0.0/16")
    ec2_api.create_internetgateway()

    ec2_api.create_vpc(:vpc_id => "vpc-23456789", :cidr_blk => "20.0.0.0/16")
    ec2_api.create_internetgateway(:igw_id => "igw-23456789", :vpc_id => "vpc-23456789")

    ec2_api.create_vpc(:vpc_id => "vpc-34567890", :cidr_blk => "30.0.0.0/16")
    ec2_api.create_internetgateway(:igw_id => "igw-34567890", :vpc_id => "vpc-34567890")

    ec2_api.create_vpc_security_group(:group_name => "Protected", :empty => true, :vpc_id => "vpc-12345678")
    options = {:group_name => "Protected", :ip_protocol => "tcp", :from_port => 22,
        :to_port => 22, :cidr_ip => "10.0.1.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    ec2_api.create_vpc_security_group(:group_name => "Affected Windows", :empty => true, :vpc_id => "vpc-23456790")
    options = {:group_name => "Affected Windows", :ip_protocol => "tcp", :from_port => 3386,
        :to_port => 3395, :cidr_ip => "0.0.0.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    ec2_api.create_vpc_security_group(:group_name => "Affected Linux", :empty => true, :vpc_id => "vpc-34567890")
    options = {:group_name => "Affected Linux", :ip_protocol => "tcp", :from_port => 22,
        :to_port => 22, :cidr_ip => "0.0.0.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    puts "describe security groups: #{ec2_api.describe_security_groups().inspect}"
    params = {
      :ec2_api_handler => ec2_api,
      :critical_ports => [22, 3389],
      :logger => logger,
    }
    script = VpcCriticalPortsAudit.new(params)
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
