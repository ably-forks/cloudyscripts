require 'help/remote_command_handler'
require 'help/state_change_listener'
require 'scripts/ec2/audit_via_ssh'
require 'AWS'


module SecludIT
module CloudyScripts


class StateChangeListenerSample < StateChangeListener

  def state_changed(state)
    puts "state change notification: new state = #{state.to_s} #{state.done? ? '(terminated)' : ''}"
  end

  def new_message(message, level = Logger::DEBUG)
    puts "#{level}: new progress message = #{message}"
  end

end


class AuditViaSshSampleCode

  def self.run()
    aws_access_key = "MyAccessKey"	# Your AWS access key
    aws_secret_key = "MySecretKey"	# Your AWS secret key

    aws_access_key = "AKIAJHUQRMJ2N43R45KA"	# Your AWS access key
    aws_secret_key = "zosvhonNGRsvnzN8pJhhQAYlGe+LMyD3PI1byt0+"	# Your AWS secret key

    aws_endpoint = "ec2.us-east-1.amazonaws.com"
    aws_ami_id = "ami-72d8201b"		# Your EC2 AMI to Audit
    aws_instance_id = "i-4f495a21"	# Your EC2 Instance to Audit

    aws_ec2_api = AWS::EC2::Base.new(:access_key_id => aws_access_key, :secret_access_key => aws_secret_key, :server => aws_endpoint)
    ssh = RemoteCommandHandler.new()
    listener = SecludIT::CloudyScripts::StateChangeListenerSample.new()
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    puts "describe images: #{aws_ec2_api.describe_images(:image_id => aws_ami_id).inspect}"
    params = {
      #:ami_id => aws_ami_id,
      :instance_id => aws_instance_id,
      :ec2_api_handler => aws_ec2_api,
      :sec_grp_name => "CloudyScripts Open FW",
      :logger => logger,
      :remote_command_handler => ssh,
      :name => "Audit via SSH #{Time.now.to_i}",
      :description => "CloudyScripts: Audit via SSH...", 
      :audit_type => "SSH",
      :ssh_user => "root",
      :ssh_key_file => "/root/fdt_us_east.pem",
      :ssh_key_name => "fdt_us_east"
    }
    script = AuditViaSsh.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    #puts "results = #{script.get_execution_result().inspect}"
    puts "== > Results of SSH Audit: Audit Status: #{script.get_execution_result()[:done]}"
    script.get_execution_result()[:audit_test].each() {|value|
      puts "  Name: #{value[:name]},\tStatus: #{value[:status]}\n  Desc: #{value[:desc]}"
    }
    puts "done in #{endtime-starttime}s"
  end
end

end
end


#
# Launch Simple test
#
SecludIT::CloudyScripts::AuditViaSshSampleCode.run() 
