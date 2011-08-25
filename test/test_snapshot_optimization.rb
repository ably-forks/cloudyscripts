require "mock/mocked_ec2_api"
require "mock/mocked_state_change_listener"

require "scripts/ec2/snapshot_optimization"

require 'test/unit'

class TestSnapshotOptimization < Test::Unit::TestCase
  def test_execution
    three_days_ago = Time.at((Time.now.to_i - 24*60*60)).to_s
    ec2_api = MockedEc2Api.new
    ec2_api.create_instance("i-11111", ['no','matter'], ['tag-set'])
    ec2_api.create_volume(:volume_id => "vol-11111", :availability_zone => "us-east-1", :create_time => three_days_ago)
    ec2_api.create_volume(:volume_id => "vol-22222", :availability_zone => "us-east-1", :create_time => three_days_ago)
    ec2_api.create_volume(:volume_id => "vol-33333", :availability_zone => "us-east-1", :create_time => Time.now.to_s)
    ec2_api.attach_volume(:volume_id => "vol-11111", :instance_id => "i-11111")
    ec2_api.create_snapshot("vol-44444")
    ec2_api.create_snapshot("vol-44444")
    ec2_api.create_snapshot("vol-44444")
    ec2_api.create_snapshot("vol-44444")
    ec2_api.create_snapshot("vol-44444")
    #
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    puts "describe security groups: #{ec2_api.describe_security_groups().inspect}"
    params = {
      :ec2_api_handler => ec2_api,
      :remote_command_handler => RemoteCommandHandler.new,
      :delete_snapshots => false,
      :max_duplicate_snapshots => 2,
      :delete_volumes => false,
      :logger => logger,
    }
    script = SnapshotOptimization.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    puts "results = #{script.get_execution_result().inspect}"
    assert script.get_execution_result[:done]
    assert !script.get_execution_result[:failed]
    assert_not_nil script.get_execution_result[:duplicate_snapshots]
    assert_equal 3, script.get_execution_result[:duplicate_snapshots].size #3 out of 5 as specified in the params
    assert_not_nil script.get_execution_result[:orphan_volumes]
    assert_equal 1, script.get_execution_result[:orphan_volumes].size
    assert_equal "vol-22222", script.get_execution_result[:orphan_volumes][0]
    puts "done in #{endtime-starttime}s"
  end

  def test_execution_empty
    ec2_api = MockedEc2Api.new
    #
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    puts "describe security groups: #{ec2_api.describe_security_groups().inspect}"
    params = {
      :ec2_api_handler => ec2_api,
      :remote_command_handler => RemoteCommandHandler.new,
      :delete_snapshots => false,
      :max_duplicate_snapshots => 2,
      :delete_volumes => false,
      :logger => logger,
    }
    script = SnapshotOptimization.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    puts "results = #{script.get_execution_result().inspect}"
    assert script.get_execution_result[:done]
    assert !script.get_execution_result[:failed]
    assert_not_nil script.get_execution_result[:duplicate_snapshots]
    assert_equal 0, script.get_execution_result[:duplicate_snapshots].size #3 out of 5 as specified in the params
    assert_not_nil script.get_execution_result[:orphan_volumes]
    assert_equal 0, script.get_execution_result[:orphan_volumes].size
    puts "done in #{endtime-starttime}s"
  end


end
