require "mock/mocked_ec2_api"
require "mock/mocked_remote_command_handler"
require "mock/mocked_state_change_listener"
require "help/remote_command_handler"
require "mock/mocked_audit_lib"
require "scripts/ec2/audit_via_ssh"

require 'test/unit'

#XXX: DOES NOT WORK AS a mocked API is required for SSH AUDIT

class TestAuditViaSsh < Test::Unit::TestCase

  def test_execution
    ec2_api = MockedEc2Api.new
    ec2_api.rootDeviceType = "ebs"
    ec2_target_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "My SecGrp")
    options = {:group_name => "My SecGrp", :ip_protocol => "tcp", :from_port => 22,
               :to_port => 22, :cidr_ip => "0.0.0.0/0"}
    ec2_api.authorize_security_group_ingress(options)
    ssh = MockedRemoteCommandHandler.new
    listener = MockedStateChangeListener.new
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    audit = MockedAuditLib.new(:benchmark => "./lib/audit/benchmark_ssh.zip", :attachment_dir => "/tmp/",
                               :connection_type => :ssh, 
                               :connection_params => {:user => "root",
                                                      :keys => "/tmp/cloudyscripts_test.pem",
                                                      :host => "pipo.test.com",
                                                      :paranoid => false, 
                                                      :verbose => :warn},
                               :logger => nil)
    puts "describe images: #{ec2_api.describe_images(:image_id => 'ami-who-cares').inspect}"
    params = {
      :ami_id => "ami-who-cares",
      :ec2_api_handler => ec2_api,
      :sec_grp_name => "My SecGrp",
      :source_ssh_keyfile => "/tmp/cloudyscripts_test.pem",
      :source_ssh_keydata => "1234567890",
      :source_key_name => "cloudyscripts_test",
      :logger => logger,
      :remote_command_handler => ssh,
      :name => "Audit via SSH #{Time.now.to_i}",
      :description => "CloudyScripts: Audit via SSH...", 
      :audit_type => "SSH",
      :ssh_user => "root",
      :ssh_keys => "/tmp/cloudyscripts_test.pem",
      :audit => audit
    }
    script = AuditViaSsh.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    puts "results = #{script.get_execution_result().inspect}"
    assert script.get_execution_result[:done]
    assert !script.get_execution_result[:failed]
    puts "done in #{endtime-starttime}s"
  end

end
