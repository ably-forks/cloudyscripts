require "test/mock/mocked_ec2_api"
require "test/mock/mocked_remote_command_handler"
require "test/mock/mocked_state_change_listener"
require "lib/help/remote_command_handler"

require "lib/scripts/ec2/copy_mswindows_ami"

require 'test/unit'
require 'pp'

class TestCopyMsWindowsAmi < Test::Unit::TestCase
  def test_execution
    # create source
    source_ec2_api = MockedEc2Api.new
    source_ec2_api.create_security_group(:group_name => "default")
    win_ami = source_ec2_api.create_dummy_image(:ami_id => "ami-12345678", 
      :name => "MS Windows 2008 Server", :desc => "MS Windows AMI to convert", 
      :root_device_name => "/dev/sda1", :root_device_type => "ebs", 
      :platform => "windows", :arch => "i386")
    linux_src_ami = source_ec2_api.create_dummy_image(:ami_id => "ami-23f53c4a", 
      :name => "AWS Linux Source", :desc => "AWS Linux Source Helper AMI", 
      :root_device_name => "/dev/sda1", :root_device_type => "ebs", 
      :platform => "linux", :arch => "i386")
    win_snap = source_ec2_api.create_snapshot(:volume_id => "vol-12345678", :size => 10)
    # create target
    target_ec2_api = MockedEc2Api.new
    target_ec2_api.create_security_group(:group_name => "default")
    win_hlp_ami = target_ec2_api.create_dummy_image(:ami_id => "ami-87654321", 
      :name => "MS Windows 2008 Server", :desc => "MS Windows Helper AMI", 
      :root_device_name => "/dev/sda1", :root_device_type => "ebs", 
      :platform => "windows", :arch => "i386")
    linux_tgt_ami = target_ec2_api.create_dummy_image(:ami_id => "ami-013a6544", 
      :name => "AWS Linux Target", :desc => "AWS Linux Target Helper AMI", 
      :root_device_name => "/dev/sda1", :root_device_type => "ebs", 
      :platform => "linux", :arch => "i386")
    #win_hlp_snap = target_ec2_api.create_snapshot(:volume_id => "vol-12345678", :size => 10)
    # check Mocked API
    puts "Snapshot:"
    pp win_snap
    puts "MS Windows AMI:"
    pp source_ec2_api.describe_images(:image_id => win_ami[:ami_id])
    puts "Linux Source Helper AMI:"
    pp source_ec2_api.describe_images(:image_id => linux_src_ami[:ami_id])
    puts "MS Windows helper AMI:"
    pp target_ec2_api.describe_images(:image_id => win_hlp_ami[:ami_id])
    puts "Linux Target Helper AMI:"
    pp target_ec2_api.describe_images(:image_id => linux_tgt_ami[:ami_id])

    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    puts "describe images: #{source_ec2_api.describe_images(:image_id => 'ami-who-cares').inspect}"
    params = {
      :ami_id => "ami-12345678",
      :helper_ami_id => "ami-87654321",
      :source_ami_id => "ami-23f53c4a",
      :ec2_api_handler => source_ec2_api,
      :target_ec2_handler => target_ec2_api,
      :source_ssh_username => "root",
      :source_key_name => "jungmats",
      :source_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :source_ssh_keydata => "1234567890",
      :target_ami_id => "ami-013a6544",
      :target_ssh_username => "root",
      :target_key_name => "jungmats",
      :target_ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :target_ssh_keydata => "1234567890",
      :logger => logger,
      :remote_command_handler => ssh,
      :name => "Copy of an AMI #{Time.now.to_i}",
      :description => "Cloudy_Scripts: Copy of AMI..."
    }

    script = CopyMsWindowsAmi.new(params)
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
