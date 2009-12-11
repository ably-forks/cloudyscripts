require 'rubygems'
require 'net/ssh'
require 'AWS'

require "../test/mock/mocked_ec2_api"
require "../test/mock/mocked_remote_command_handler"

require "scripts/ec2/dm_encrypt"

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
if script.get_execution_result[:failed] == nil || script.get_execution_result[:failed]
  puts "script failed: #{script.get_execution_result[:failure_reason]}"
end

puts "done"
