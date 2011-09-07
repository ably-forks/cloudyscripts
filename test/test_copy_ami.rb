require "mock/mocked_ec2_api"
require "mock/mocked_remote_command_handler"
require "mock/mocked_state_change_listener"
require "help/remote_command_handler"

require "scripts/ec2/copy_ami"

require 'test/unit'

class TestCopyAmi < Test::Unit::TestCase
  def test_execution
    ec2_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "default")
    ec2_api.rootDeviceType = "ebs"
    ec2_target_api = MockedEc2Api.new
    ec2_target_api.create_security_group(:group_name => "default")
    snap = ec2_api.create_snapshot("x-12345")
    puts "snap = #{snap.inspect}"
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    puts "describe images: #{ec2_api.describe_images(:image_id => 'ami-who-cares').inspect}"
    params = {
      :ami_id => "ami-who-cares",
      :ec2_api_handler => ec2_api,
      :target_ec2_handler => ec2_target_api,
      :source_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :source_ssh_keydata => "1234567890",
      :target_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :target_ssh_keydata => "1234567890",
      :source_key_name => "jungmats",
      :target_key_name => "jungmats",
      :target_ami_id => "ami-d936d9b0",
      :logger => logger,
      :remote_command_handler => ssh,
      :name => "Copy of an AMI #{Time.now.to_i}",
      :description => "Cloudy_Scripts: Copy of AMI..."
    }
    script = CopyAmi.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    puts "results = #{script.get_execution_result().inspect}"
    assert script.get_execution_result[:image_id] != nil
    assert script.get_execution_result[:done]
    assert !script.get_execution_result[:failed]
    puts "done in #{endtime-starttime}s"
  end

end
