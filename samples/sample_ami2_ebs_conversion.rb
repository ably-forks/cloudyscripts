require 'help/remote_command_handler'
require 'help/state_change_listener'
require 'scripts/ec2/ami2_ebs_conversion'
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


class ConvertAmiSampleCode

  def self.run()
    aws_access_key = "MyAccessKey"	# Your AWS access key
    aws_secret_key = "MySecretKey"	# Your AWS secret key

    aws_source_endpoint = "ap-southeast-1.ec2.amazonaws.com"
    source_ssh_user = "ubuntu"
    source_ssh_key_file = "/root/fdt_ap_southeast.pem"
    source_ssh_key_name = "fdt_ap_southeast"
    aws_ami_id = "ami-25e39c77"		# Your EC2 AMI to Convert
    security_group_name = "CloudyScripts Open FW"

    new_ami_name = "CloudyScripts AMI conversion"
    new_ami_description = "Convert AMI"

    connect_trials = 5
    connect_interval = 30

    source_ec2_api = AWS::EC2::Base.new(:access_key_id => aws_access_key, :secret_access_key => aws_secret_key, :server => aws_source_endpoint)
    ssh = RemoteCommandHandler.new()

    listener = SecludIT::CloudyScripts::StateChangeListenerSample.new()
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    puts "describe images: #{source_ec2_api.describe_images(:image_id => aws_ami_id).inspect}"

    params = {
      :remote_command_handler => ssh,
      :ec2_api_handler => source_ec2_api,
      :ami_id => aws_ami_id,
      :security_group_name => security_group_name,
      :ssh_username => source_ssh_user,
      :key_name => source_ssh_key_name,
      :ssh_keydata => File.new(source_ssh_key_file, "r").read,
      :name => new_ami_name,
      :description => new_ami_description,
      :logger => logger,
      :connect_trials => connect_trials.to_i,
      :connect_interval => connect_interval.to_i
    }

    script = Ami2EbsConversion.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    #puts "results = #{script.get_execution_result().inspect}"
    puts "== > Results of Convert AMI: #{script.get_execution_result()[:done]}"
    puts "New AMI ID: #{script.get_execution_result()[:image_id]}"
    puts "done in #{endtime-starttime}s"
  end
end

end
end


#
# Launch Simple test
#
SecludIT::CloudyScripts::ConvertAmiSampleCode.run() 
