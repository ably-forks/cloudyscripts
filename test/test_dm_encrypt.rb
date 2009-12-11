require "mock/mocked_ec2_api"
require "mock/mocked_remote_command_handler"

require "scripts/ec2/dm_encrypt"

$:.unshift File.join(File.dirname(__FILE__),'..','lib')

require 'test/unit'
#require 'dm_encrypt'

class TestDmEncrypt < Test::Unit::TestCase
  def test_execution
    rch = MockedRemoteCommandHandler.new
    ec2 = MockedEc2Api.new

    params = {
      :remote_command_handler => rch,
      :ec2_api_handler => ec2,
      :password => "password",
      :ip_address => "127.0.0.1",
      :ssh_key_file => "/Users/mats/.ssh",
      :device => "/dev/sdh",
      :device_name => "device-vol-i-12345"
    }
    script = DmEncrypt.new(params)
    script.start_script()
    assert script.get_execution_result[:failed] == nil || script.get_execution_result[:failed] == false, script.get_execution_result[:failure_reason]
    puts "done"
  end
end
