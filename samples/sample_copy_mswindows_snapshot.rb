require 'rubygems'
require 'help/remote_command_handler'
require 'help/state_change_listener'
require 'scripts/ec2/copy_mswindows_ami'
require 'AWS'


module SecludIT
module CloudyScripts


class AwsEc2Helper 

  #XXX: retrieve a getting-started-with-ebs-boot AMI of Amazon according to Amazon Region
  def self.get_starter_ami(region)
    map = {'us-east-1.ec2.amazonaws.com' => 'ami-b232d0db',
      'us-west-1.ec2.amazonaws.com' => 'ami-813968c4',
      'eu-west-1.ec2.amazonaws.com' => 'ami-df1e35ab',
      'ap-southeast-1.ec2.amazonaws.com' => 'ami-99f58acb',
      'ap-northeast-1.ec2.amazonaws.com' => 'ami-2e08a32f'
    }
    if map[region] == nil
      raise Exception.new("region not supported")
    end
    map[region]
  end

  #XXX: Basic 32-bit Amazon Linux AMI 2011.02.1 Beta
  def self.get_basic_aws_linux_ami_old(region)
   map = {'us-east-1.ec2.amazonaws.com' => 'ami-09ab6d60', #'ami-8c1fece5',
      'us-west-1.ec2.amazonaws.com' => 'ami-17eebc52', #'ami-3bc9997e',
      'eu-west-1.ec2.amazonaws.com' => 'ami-940030e0', #'ami-47cefa33',
      'ap-southeast-1.ec2.amazonaws.com' => 'ami-cec9b19c', #'ami-6af08e38',
      'ap-northeast-1.ec2.amazonaws.com' => 'ami-96b50097' #'ami-300ca731'
    }
    if map[region] == nil
      raise Exception.new("region not supported")
    end
    map[region]
  end

  # Public CloudyScripts AMI: Basic 32-bit Amazon Linux AMI 2011.02.1 Beta
  # XXX: Update on 11/11/2011 based on
  #  - Basic 32-bit Amazon Linux AMI 2011.09 (amazon/amzn-ami-2011.09.2.i386-ebs)
  def self.get_basic_aws_linux_ami(region)
    map = {'us-east-1.ec2.amazonaws.com' => 'ami-23f53c4a', #'ami-09ab6d60', #'ami-8c1fece5',
      'us-west-1.ec2.amazonaws.com' => 'ami-013a6544', #'ami-17eebc52', #'ami-3bc9997e',
      'us-west-2.ec2.amazonaws.com' => 'ami-42f77a72',
      'eu-west-1.ec2.amazonaws.com' => 'ami-f3c3fe87', #'ami-940030e0', #'ami-47cefa33',
      'ap-southeast-1.ec2.amazonaws.com' => 'ami-b4f18be6', #'ami-cec9b19c', #'ami-6af08e38',
      'ap-northeast-1.ec2.amazonaws.com' => 'ami-8a07b38b', #'ami-96b50097' #'ami-300ca731'
    }
    if map[region] == nil
      raise Exception.new("region not supported")
    end
    map[region]
  end

end


class StateChangeListenerSample < StateChangeListener

  def state_changed(state)
    puts "state change notification: new state = #{state.to_s} #{state.done? ? '(terminated)' : ''}"
  end

  def new_message(message, level = Logger::DEBUG)
    puts "#{level}: new progress message = #{message}"
  end

end


class CopyMsWindowsSnapshotSampleCode

  def self.run()
    aws_access_key = "MyAccessKey"	# Your AWS access key
    aws_secret_key = "MySecretKey"	# Your AWS secret key

    aws_source_endpoint = "us-east-1.ec2.amazonaws.com"
    aws_source_region = "us-east-1.ec2.amazonaws.com"
    source_ssh_user = "ec2-user"
    source_ssh_key_file = "/root/fdt_us_east.pem"
    source_ssh_key_name = "fdt_us_east"

    # sample: Microsoft Windows Server 2008 Base
    aws_snap_id = ""		# Your EC2 Snapshot to Copy

    aws_target_endpoint = "us-west-1.ec2.amazonaws.com"
    aws_target_region = "us-west-1.ec2.amazonaws.com"
    target_ssh_user = "ec2-user"
    target_ssh_key_file = "/root/fdt_us_west.pem"
    target_ssh_key_name = "fdt_us_west"
    new_ami_name = "CloudyScripts MS Windows AMI copy"
    new_ami_description = "Copy of MS Windows AMI ami-06ad526f from AWS US-East-1 to US-West-1"

    source_ec2_api = AWS::EC2::Base.new(:access_key_id => aws_access_key, :secret_access_key => aws_secret_key, :server => aws_source_endpoint)
    target_ec2_api = AWS::EC2::Base.new(:access_key_id => aws_access_key, :secret_access_key => aws_secret_key, :server => aws_target_endpoint)
    ssh = RemoteCommandHandler.new()

    listener = SecludIT::CloudyScripts::StateChangeListenerSample.new()
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    puts "describe snapshot: #{source_ec2_api.describe_snapshots(:snapshot_id => aws_snap_id).inspect}"

    params = {
      :snapshot_id => aws_snap_id,
      :source_ami_id => SecludIT::CloudyScripts::AwsEc2Helper.get_basic_aws_linux_ami(aws_source_region),
      :ec2_api_handler => source_ec2_api,
      :target_ec2_handler => target_ec2_api,
      :source_ssh_username => source_ssh_user,
      :source_key_name => source_ssh_key_name,
      :source_ssh_keyfile => source_ssh_key_file,
      :source_ssh_keydata => File.new(source_ssh_key_file, "r").read,
      :target_ami_id => SecludIT::CloudyScripts::AwsEc2Helper.get_basic_aws_linux_ami(aws_target_region),
      :target_ssh_username => target_ssh_user,
      :target_key_name => target_ssh_key_name,
      :target_ssh_keyfile => target_ssh_key_file,
      :target_ssh_keydata => File.new(target_ssh_key_file, "r").read,
      :logger => logger,
      :remote_command_handler => ssh,
    }

    script = CopyMsWindowsSnapshot.new(params)
    script.register_state_change_listener(listener)
    script.register_progress_message_listener(listener)
    starttime = Time.now.to_i
    script.start_script()
    endtime = Time.now.to_i
    #puts "results = #{script.get_execution_result().inspect}"
    puts "== > Results of Copy AMI: #{script.get_execution_result()[:done]}"
    puts "New AMI ID: #{script.get_execution_result()[:image_id]}"
    puts "done in #{endtime-starttime}s"
  end
end

end
end


#
# Launch Simple test
#
SecludIT::CloudyScripts::CopyMsWindowsSnapshotSampleCode.run() 
