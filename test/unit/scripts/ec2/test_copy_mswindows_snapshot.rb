require "mock/mocked_ec2_api"
require "mock/mocked_remote_command_handler"
require "mock/mocked_state_change_listener"
require "help/remote_command_handler"

require "scripts/ec2/copy_mswindows_snapshot"

require 'test/unit'

class TestCopyMsWindowsSnapshot < Test::Unit::TestCase
  def test_execution
    # create source
    source_ec2_api = MockedEc2Api.new
    source_ec2_api.create_security_group(:group_name => "default")
    linux_src_ami = source_ec2_api.create_image(:ami_id => "ami-12345678",
      :name => "AWS Linux Source", :desc => "AWS Linux Source Helper AMI",
      :root_device_name => "/dev/sda1", :root_device_type => "ebs",
      :platform => "linux", :arch => "i386")
    # create target
    target_ec2_api = MockedEc2Api.new
    target_ec2_api.create_security_group(:group_name => "default")
    linux_tgt_ami = target_ec2_api.create_image(:ami_id => "ami-013a6544", 
      :name => "AWS Linux Target", :desc => "AWS Linux Target Helper AMI", 
      :root_device_name => "/dev/sda1", :root_device_type => "ebs", 
      :platform => "linux", :arch => "i386")

    snap = source_ec2_api.create_snapshot(:volume_id => "vol-87654321", :size => 20)
    puts "snap = #{snap.inspect}"
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    params = {
      :ec2_api_handler => source_ec2_api,
      :target_ec2_handler => target_ec2_api,
      :source_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :source_ssh_keydata => "1234567890",
      :target_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :target_ssh_keydata => "1234567890",
      :source_key_name => "jungmats",
      :target_key_name => "jungmats",
      :source_ami_id => "ami-12345678",
      :target_ami_id => "ami-12345678",
      :snapshot_id => snap['snapshotId'],
      :logger => logger,
      :remote_command_handler => ssh
    }
    script = CopyMsWindowsSnapshot.new(params)
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
