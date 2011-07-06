require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
require "help/ec2_helper"
require "audit/lib/audit"
require "AWS"
require 'pp'

# Audit an AMI or an instance via an SSH connection using a specific benchmark
#

class AuditViaSsh < Ec2Script
  # Input parameters
  # * ec2_api_handler => object that allows to access the EC2 API
  # * ami_id => the ID of the AMI to be copied in another region
  # * ssh_username => The username for ssh for source-instance (default = root)
  # * key_name => Key name of the instance that manages the snaphot-volume in the source region
  # * ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]

  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:instance_id] == nil && @input_params[:instance_id] == nil
      raise Exception.new("No Instance ID or AMI ID specified")
    end
    if @input_params[:ami_id] != nil && !(@input_params[:ami_id] =~ /^ami-.*$/)
      raise Exception.new("Invalid AMI ID specified")
    end
    if @input_params[:instance_id] != nil && !(@input_params[:instance_id] =~ /^i-.*$/)
      raise Exception.new("Invalid Instance ID specified")
    end

    if @input_params[:sec_grp_name] == nil
      @input_params[:sec_grp_name] = "default"
    end
    if @input_params[:audit_type] != nil && @input_params[:audit_type].casecmp("SSH")
      @input_params[:benchmark_file] = "./lib/audit/benchmark_ssh.zip"
    else
      raise Exception.new("Invalid Audit '#{@input_params[:audit_type]}' specified")
    end
    ec2_helper = Ec2Helper.new(@input_params[:ec2_api_handler])
    if !ec2_helper.check_open_port(@input_params[:sec_grp_name], 22)
      raise Exception.new("Port 22 must be opened for security group 'default' to connect via SSH")
    end
  end

  def load_initial_state()
    AuditViaSshState.load_state(@input_params)
  end
  
  private

  # Here begins the state machine implementation
  class AuditViaSshState < ScriptExecutionState
    def self.load_state(context)
      state = context[:initial_state] == nil ? InitialState.new(context) : context[:initial_state]
      state
    end

  end

  # Start an instance and wait for it to be UP and running
  # Create a temporary directory
  class InitialState < AuditViaSshState
    def enter
      instances_info = []
      tmp_dir = ""
      if @context[:ami_id] != nil
        instance_infos = launch_instance(@context[:ami_id], @context[:ssh_key_name], @context[:sec_grp_name], nil, "t1.micro")
        tmp_dir = "/tmp/#{@context[:ami_id]}-#{Time.now().to_i}"
      elsif @context[:instance_id] != nil
        instance_infos = start_instance(@context[:instance_id])
        tmp_dir = "/tmp/#{@context[:instance_id]}-#{Time.now().to_i}"
      else
        raise Exception.new("No Instance ID or AMI ID specified (should have been catched earlier)")
      end
      @context[:instance_id] = instance_infos[0]
      @context[:public_dns_name] = instance_infos[1]
      @context[:tmp_dir] = tmp_dir
      #puts "DEBUG: Audit Scripts"
      #pp @context

      Dir::mkdir(tmp_dir)
      if FileTest::directory?(tmp_dir)
        post_message("local temporary directory created")
      end

      LaunchAuditViaSsh.new(@context)
    end
  end

  # Launch the audit via SSH
  class LaunchAuditViaSsh < AuditViaSshState
    def enter
      audit = Audit.new(:benchmark => @context[:benchmark_file], :attachment_dir => @context[:tmp_dir],
                        :connection_type => :ssh, 
                        :connection_params => {:user => @context[:ssh_user],
                                               :keys => @context[:ssh_key_file],
                                               :host => @context[:public_dns_name],
                                               :paranoid => false},
                                               :logger => nil)
      audit.start(false)
      @context[:result][:audit_test] = []
      audit.results.each() {|key, value|
        if key =~ /^SSH_.*$/
          puts "DEBUG: Key: #{key}, Result: #{value.result}, Desc: #{value.rule.description}"
          @context[:result][:audit_test] << {:name => key, :desc => value.rule.description, :status => value.result}
          post_message("== > Test #{key}: Status: #{value.result.eql?("pass") ? "OK" : "NOK"}")
        end
      }
      CleanUpAuditViaSsh.new(@context)
    end
  end

  # Terminate an instance
  class CleanUpAuditViaSsh < AuditViaSshState
    def enter
      if @context[:ami_id] != nil
        shut_down_instance(@context[:instance_id])
      elsif @context[:instance_id] != nil
        #TODO: stop the instance only if you have started it
        #stop_instance(@context[:instance_id])
      else
        raise Exception.new("No Instance ID or AMI ID specified (should have been catched earlier)")
      end

      AnalyseAuditViaSsh.new(@context)
    end
  end

  # Analyse audit via SSH results 
  class AnalyseAuditViaSsh < AuditViaSshState
    def enter
      
      Done.new(@context)
    end
  end

  # Script done.
  class Done < AuditViaSshState
    def done?
      true
    end
  end
  
end
