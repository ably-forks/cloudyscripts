$:.unshift File.join(File.dirname(__FILE__),'..','lib')

require "mock/mocked_ec2_api"
require "mock/mocked_remote_command_handler"
require "mock/mocked_state_change_listener"

require "scripts/ec2/dm_encrypt"

require 'test/unit'
#require 'dm_encrypt'

class TestDmEncrypt < Test::Unit::TestCase
  def test_execution
    rch = MockedRemoteCommandHandler.new
    ec2 = MockedEc2Api.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    params = {
      :remote_command_handler => rch,
      :ec2_api_handler => ec2,
      :paraphrase => "paraphrase",
      :ip_address => "127.0.0.1",
      :ssh_key_file => "/Users/mats/.ssh",
      :device => "/dev/sdh",
      :device_name => "device-vol-i-12345",
      :storage_path => "/mnt/encrypted_drive",
      :logger => logger
    }
    script = DmEncrypt.new(params)
    script.register_state_change_listener(listener)
    script.start_script()
    assert script.get_execution_result[:failed] == nil || script.get_execution_result[:failed] == false, script.get_execution_result[:failure_reason]
    puts "done"
  end
end
