require "test/mock/mocked_ec2_api"
require "test/mock/mocked_remote_command_handler"
require "test/mock/mocked_state_change_listener"
require "lib/help/remote_command_handler"

require "lib/scripts/ec2/download_snapshot"

require 'test/unit'

class TestDownloadSnapshot < Test::Unit::TestCase
  def test_execution
    ec2_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "MatsGroup")
    ec2_api.authorize_security_group_ingress(:group_name => "MatsGroup",
      :ip_protocol => "tcp", :from_port => 80, :to_port => 80, :cidr_ip => "0.0.0.0/0")
    ec2_api.rootDeviceType = "ebs"
    linux_src_ami = ec2_api.create_dummy_image(:ami_id => "ami-12345678",
      :name => "AWS Linux", :desc => "AWS Linux AMI",
      :root_device_name => "/dev/sda1", :root_device_type => "ebs",
      :platform => "linux", :arch => "i386")
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    params = {
      :ec2_api_handler => ec2_api,
      :security_group_name => "MatsGroup",
      :remote_command_handler => ssh,
      :ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :key_name => "jungmats",
      :ami_id => "ami-12345678",
      :snapshot_id => "snap-12345",
      :wait_time => 30,
      :logger => logger
    }
    script = DownloadSnapshot.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    assert script.get_execution_result[:failed] == nil || script.get_execution_result[:failed] == false, script.get_execution_result[:failure_reason]
    puts "done in #{endtime-starttime}s"
    puts "#{script.get_execution_result().inspect}"
  end

  def test_execution_with_port_80_closed
    ec2_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "MatsGroup")
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    params = {
      :ec2_api_handler => ec2_api,
      :security_group_name => "MatsGroup",
      :remote_command_handler => ssh,
      :ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :key_name => "jungmats",
      :ami_id => "ami-d936d9b0",
      :snapshot_id => "snap-12345",
      :wait_time => 30,
      :logger => logger
    }
    script = DownloadSnapshot.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    begin
      script.start_script()
      assert false
    rescue Exception => e
      assert true
    end
    endtime = Time.now.to_i
    puts "done in #{endtime-starttime}s"
    puts "#{script.get_execution_result().inspect}"
  end

end
