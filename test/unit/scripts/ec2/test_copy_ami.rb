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
    linux_src_ami = ec2_api.create_image(:ami_id => "ami-12345678",
      :name => "AWS Linux", :desc => "AWS Linux AMI",
      :root_device_name => "/dev/sda1", :root_device_type => "ebs",
      :platform => "linux", :arch => "i386")
    ec2_target_api = MockedEc2Api.new
    ec2_target_api.create_security_group(:group_name => "default")
    ec2_target_api.rootDeviceType = "ebs"
    target_src_ami = ec2_target_api.create_image(:ami_id => "ami-12345678",
      :name => "AWS Linux Helper", :desc => "AWS Linux Helper AMI",
      :root_device_name => "/dev/sda1", :root_device_type => "ebs",
      :platform => "linux", :arch => "i386")
    snap = ec2_api.create_snapshot(:volume_id => "vol-87654321")
    puts "snap = #{snap.inspect}"
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    #puts "describe images: #{ec2_api.describe_images(:image_id => 'ami-who-cares').inspect}"
    puts "AWS Linux AMI to copy:"
    pp ec2_api.describe_images(:image_id => "ami-12345678")
    params = {
      :ami_id => "ami-12345678",
      :ec2_api_handler => ec2_api,
      :target_ec2_handler => ec2_target_api,
      :source_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :source_ssh_keydata => "1234567890",
      :target_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :target_ssh_keydata => "1234567890",
      :source_key_name => "jung mats",
      :target_key_name => "jung mats",
      :target_ami_id => "ami-12345678",
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
