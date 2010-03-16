require "mock/mocked_ec2_api"
require "mock/mocked_remote_command_handler"
require "mock/mocked_state_change_listener"
require "help/remote_command_handler"

require "scripts/ec2/download_snapshot"

require 'test/unit'

class TestDownloadSnapshot < Test::Unit::TestCase
  def test_execution
    ec2_api = MockedEc2Api.new
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
    script.start_script()
    endtime = Time.now.to_i
    assert script.get_execution_result[:failed] == nil || script.get_execution_result[:failed] == false, script.get_execution_result[:failure_reason]
    puts "done in #{endtime-starttime}s"
    puts "#{script.get_execution_result().inspect}"
  end

end
