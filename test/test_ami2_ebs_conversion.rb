require "mock/mocked_ec2_api"
require "mock/mocked_remote_command_handler"
require "mock/mocked_state_change_listener"
require "help/remote_command_handler"

require "scripts/ec2/ami2_ebs_conversion"

require 'test/unit'

class TestAmi2EbsConversion < Test::Unit::TestCase
  def test_execution
    ec2_api = MockedEc2Api.new
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    params = {
      :ami_id => "ami-8729cfee",
      :ec2_api_handler => ec2_api,
      :security_group_name => "MatsGroup",
      :remote_command_handler => ssh,
      :ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :key_name => "jungmats",
    }

=begin
    params[:instance_id] = "i-5f567837"
    params[:device] = "/dev/sdj"
    params[:volume_id] = "vol-d461a6bd"
    params[:dns_name] = "ec2-75-101-244-35.compute-1.amazonaws.com"
    params[:path] = "/mnt/tmp_vol-d461a6bd"
    #params[:initial_state] = Ami2EbsConversion::StorageAttached.new(params)
    #ssh.connect_with_keyfile(params[:dns_name], params[:ssh_keyfile])
    #params[:initial_state] = Ami2EbsConversion::FileSystemMounted.new(params)
    #params[:initial_state] = Ami2EbsConversion::CopyDone.new(params)
    #params[:initial_state] = Ami2EbsConversion::VolumeDetached.new(params)
    params[:snapshot_id] = "snap-a11b64c8"
    #params[:initial_state] = Ami2EbsConversion::SnapshotCreated.new(params)
    #params[:initial_state] = Ami2EbsConversion::VolumeDeleted.new(params)
    params[:initial_state] = Ami2EbsConversion::SnapshotRegistered.new(params)
=end
    script = Ami2EbsConversion.new(params)
    script.register_state_change_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    assert script.get_execution_result[:failed] == nil || script.get_execution_result[:failed] == false, script.get_execution_result[:failure_reason]
    puts "done in #{endtime-starttime}s"
    puts "#{script.get_execution_result().inspect}"
  end

  def test_resume
    #ec2_api = AWS::EC2::Base.new(:access_key_id => "03AD8BV6FBQHFY3MZ4G2", :secret_access_key => "D9j14KgaMIVDxWhFyc9ASQWBH/BxyLO3hl0vuwkC")
    ec2_api = MockedEc2Api.new
    #ssh = RemoteCommandHandler.new
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    params = {
      :ami_id => "ami-8729cfee",
      :ec2_api_handler => ec2_api,
      :security_group_name => "MatsGroup",
      :remote_command_handler => ssh,
      :ssh_keyfile => "/Users/mats/.ssh/jungmats.pem",
      :key_name => "jungmats",
    }

    params[:instance_id] = "i-5f567837"
    params[:device] = "/dev/sdj"
    params[:volume_id] = "vol-d461a6bd"
    params[:dns_name] = "ec2-75-101-244-35.compute-1.amazonaws.com"
    params[:path] = "/mnt/tmp_vol-d461a6bd"
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
