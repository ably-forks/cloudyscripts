require "test/mock/mocked_ec2_api"
require "test/mock/mocked_remote_command_handler"
require "test/mock/mocked_state_change_listener"
require "lib/help/remote_command_handler"

require "lib/scripts/ec2/ami2_ebs_conversion"

require 'test/unit'

class TestAmi2EbsConversion < Test::Unit::TestCase
  def test_the_execution
    ec2_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "default")
    ec2_api.create_security_group(:group_name => "MatsGroup")
    ec2_api.rootDeviceType = "ebs"
    linux_src_ami = ec2_api.create_dummy_image(:ami_id => "ami-12345678",
      :name => "AWS Linux", :desc => "AWS Linux AMI",
      :root_device_name => "/dev/sda1", :root_device_type => "ebs",
      :platform => "linux", :arch => "i386")
    puts "ec2_api.describe_security_groups => #{ec2_api.describe_security_groups.inspect}"
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    params = {
      :ami_id => "ami-12345678",
      :ec2_api_handler => ec2_api,
      :security_group_name => "MatsGroup",
      :remote_command_handler => ssh,
      :ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :key_name => "jungmats",
      :logger => logger
    }
    script = Ami2EbsConversion.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    assert script.get_execution_result[:failed] == nil || script.get_execution_result[:failed] == false, script.get_execution_result[:failure_reason]
    puts "done in #{endtime-starttime}s"
    puts "#{script.get_execution_result().inspect}"
  end

  def test_resume
    ec2_api = MockedEc2Api.new
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    params = {
      :ami_id => "ami-12345678",
      :ec2_api_handler => ec2_api,
      :security_group_name => "MatsGroup",
      :remote_command_handler => ssh,
      :ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :key_name => "jungmats",
    }

    params[:instance_id] = "i-5f567837"
    ec2_api.create_dummy_instance("i-5f567837", "ami-1245678", "running", "who.cares", "public.dns", "jungmats", ["MatsGroup"])
    params[:device] = "/dev/sdj"
    params[:volume_id] = "vol-d461a6bd"
    ec2_api.create_dummy_volume("vol-d461a6bd", "timezone")
    params[:dns_name] = "ec2-75-101-244-35.compute-1.amazonaws.com"
    params[:path] = "/mnt/tmp_vol-d461a6bd"
    params[:availability_zone] = "whatever"
    params[:initial_state] = Ami2EbsConversion::StorageAttached.new(params)

    script = Ami2EbsConversion.new(params)
    script.register_state_change_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    assert script.get_execution_result[:failed] == nil || script.get_execution_result[:failed] == false, script.get_execution_result[:failure_reason]
    puts "done in #{endtime-starttime}s"
    puts "#{script.get_execution_result().inspect}"
  end

end
