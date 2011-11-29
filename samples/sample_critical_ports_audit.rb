require 'help/remote_command_handler'
require 'help/state_change_listener'
require 'scripts/ec2/critical_ports_audit'
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


class CriticalPortsAuditSampleCode

  def self.run()
    aws_access_key = "MyAccessKey"	# Your AWS access key
    aws_secret_key = "MySecretKey"	# Your AWS secret key

    aws_source_endpoint = "us-east-1.ec2.amazonaws.com"
    critical_ports = {
      22 => "SSH",
      23 => "telnet",
      3389 => "RDP",
      5500 => "VNC",
      389 => "LDAP",
      1433 => "MSSQL",
      5432 => "Postgres",
      3306 => "MySQL",
      10000 => "Webmin"
    }
 
    source_ec2_api = AWS::EC2::Base.new(:access_key_id => aws_access_key, :secret_access_key => aws_secret_key, :server => aws_source_endpoint)

    listener = SecludIT::CloudyScripts::StateChangeListenerSample.new()
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    params = {
      :ec2_api_handler => source_ec2_api,
      :logger => logger,
      :critical_ports => critical_ports.keys
    }
    script = CriticalPortsAudit.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i

    puts "== > Results of CriticalPort Audit: #{script.get_execution_result()[:done]}"
    puts "Critical Ports Found: #{script.get_execution_result()[:affected_groups]}"
    puts "Critical Ports Found: #{script.get_execution_result()[:affected_groups].to_yaml}"
    puts "done in #{endtime-starttime}s"
  end
end

end
end


#
# Launch Simple test
#
SecludIT::CloudyScripts::CriticalPortsAuditSampleCode.run() 
