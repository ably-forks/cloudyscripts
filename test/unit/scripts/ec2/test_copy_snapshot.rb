require "mock/mocked_ec2_api"
require "mock/mocked_remote_command_handler"
require "mock/mocked_state_change_listener"
require "help/remote_command_handler"

require "scripts/ec2/copy_snapshot"

require 'test/unit'

class TestCopySnapshot < Test::Unit::TestCase
  def test_execution
    ec2_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "default")
    ec2_target_api = MockedEc2Api.new
    ec2_target_api.create_security_group(:group_name => "default")
    snap = ec2_api.create_snapshot("x-12345")
    puts "snap = #{snap.inspect}"
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    params = {
      :ec2_api_handler => ec2_api,
      :target_ec2_handler => ec2_target_api,
      :source_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :source_ssh_keydata => "1234567890",
      :target_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :target_ssh_keydata => "1234567890",
      :source_key_name => "jungmats",
      :target_key_name => "jungmats",
      :source_ami_id => "ami-d936d9b0",
      :target_ami_id => "ami-d936d9b0",
      :snapshot_id => snap['snapshotId'],
      :logger => logger,
      :remote_command_handler => ssh
    }
    script = CopySnapshot.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    assert script.get_execution_result[:snapshot_id] != nil
    assert script.get_execution_result[:done]
    assert !script.get_execution_result[:failed]
    puts "done in #{endtime-starttime}s"
    puts "#{script.get_execution_result().inspect}"
  end

end
