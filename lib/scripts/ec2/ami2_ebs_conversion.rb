require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
#require "help/dm_crypt_helper"
require "AWS"

class AWS::EC2::Base
  def register_image_updated(options)
    params = {}
    params["Name"] = options[:name].to_s
    params["BlockDeviceMapping.1.Ebs.SnapshotId"] = options[:snapshot_id].to_s
    params["BlockDeviceMapping.1.DeviceName"] = options[:root_device_name].to_s
    params["Description"] = options[:description].to_s
    params["KernelId"] = options[:kernel_id].to_s
    params["RamdiskId"] = options[:ramdisk_id].to_s
    params["Architecture"] = options[:architecture].to_s
    params["RootDeviceName"] = options[:root_device_name].to_s
    return response_generator(:action => "RegisterImage", :params => params)
  end
end

# Creates a bootable EBS storage from an existing AMI.
#

class Ami2EbsConversion < Ec2Script
  # Input parameters
  # * aws_access_key => the Amazon AWS Access Key (see Your Account -> Security Credentials)
  # * aws_secret_key => the Amazon AWS Secret Key
  # * ami_id => the ID of the AMI to be converted
  # * security_group_name => name of the security group to start
  # * ssh_key_data => Key information for the security group that starts the AMI [if not set, use ssh_key_files]
  # * ssh_key_files => Key information for the security group that starts the AMI
  # * remote_command_handler => object that allows to connect via ssh and execute commands (optional)
  # * ec2_api_handler => object that allows to access the EC2 API (optional)
  # * ec2_api_server => server to connect to (option, default is us-east-1.ec2.amazonaws.com)
  # * name => the name of the AMI to be created
  # * description => description on AMI to be created (optional)
  # * temp_device_name => [default /dev/sdj] device name used to attach the temporary storage; change this only if there's already a volume attacged as /dev/sdj (optional, default is /dev/sdj)
  # * root_device_name"=> [default /dev/sda1] device name used for the root device (optional)
  def initialize(input_params)
    super(input_params)
  end

  # Executes the script.
  def start_script()
    begin
      # optional parameters and initialization
      if @input_params[:name] == nil
        @input_params[:name] = "Boot EBS (for AMI #{@input_params[:ami_id]}) at #{Time.now.strftime('%d/%m/%Y %H.%M.%S')}"
      else
      end
      if @input_params[:description] == nil
        @input_params[:description] = @input_params[:name]
      end
      if @input_params[:temp_device_name] == nil
        @input_params[:temp_device_name] = "/dev/sdj"
      end
      if @input_params[:root_device_name] == nil
        @input_params[:root_device_name] = "/dev/sda1"
      end
      # start state machine
      current_state = Ami2EbsConversionState.load_state(@input_params)
      @state_change_listeners.each() {|listener|
        current_state.register_state_change_listener(listener)
      }
      end_state = current_state.start_state_machine()
      if end_state.failed?
        @result[:failed] = true
        @result[:failure_reason] = current_state.end_state.failure_reason
        @result[:end_state] = current_state.end_state
      else
        @result[:failed] = false
      end
    rescue Exception => e
      @logger.warn "exception during encryption: #{e}"
      @logger.warn e.backtrace.join("\n")
      err = e.to_s
      err += " (in #{current_state.end_state.to_s})" unless current_state == nil
      @result[:failed] = true
      @result[:failure_reason] = err
      @result[:end_state] = current_state.end_state unless current_state == nil
    ensure
      begin
      @input_params[:remote_command_handler].disconnect
      rescue Exception => e2
      end
    end
    #
    @result[:done] = true
  end

  # Returns a hash with the following information:
  # :done => if execution is done
  #
  def get_execution_result
    @result
  end
  
  private

  # Here begins the state machine implementation
  class Ami2EbsConversionState < ScriptExecutionState
    def self.load_state(context)
      state = context[:initial_state] == nil ? InitialState.new(context) : context[:initial_state]
      state
    end

    def connect
      if @context[:remote_command_handler] == nil
        @context[:remote_command_handler] = RemoteCommandHandler.new
      end
      connected = false
      remaining_trials = 3
      while !connected && remaining_trials > 0
        remaining_trials -= 1
        if @context[:ssh_keyfile] != nil
          begin
            @context[:remote_command_handler].connect_with_keyfile(@context[:dns_name], @context[:ssh_keyfile])
            connected = true
          rescue Exception => e
            @logger.info("connection failed due to #{e}")
            @logger.debug(e.backtrace.join("\n"))
          end
        elsif @context[:ssh_keydata] != nil
          begin
            @context[:remote_command_handler].connect(@context[:dns_name], "root", @context[:ssh_keydata])
            connected = true
          rescue Exception => e
            @logger.info("connection failed due to #{e}")
            @logger.debug(e.backtrace.join("\n"))
          end
        else
          raise Exception.new("no key information specified")
        end
        if !connected
          sleep(5) #try again
        end
      end
      if !connected
        raise Exception.new("connection attempts stopped")
      end
      @context[:result][:os] = @context[:remote_command_handler].retrieve_os()
      @logger.info "connected to #{@context[:dns_name]}"
    end

  end

  # Nothing done yet. Start by instantiating an AMI (in the right zone?)
  # which serves to create 
  class InitialState < Ami2EbsConversionState
    def enter
      startup_ami()
    end

    private

    def startup_ami()
      @logger.debug "start up AMI #{@context[:ami_id]}"
      res = @context[:ec2_api_handler].run_instances(:image_id => @context[:ami_id], 
        :security_group => @context[:security_group_name], :key_name => @context[:key_name])
      instance_id = res['instancesSet']['item'][0]['instanceId']
      @context[:instance_id] = instance_id
      @logger.info "started instance #{instance_id}"
      #availability_zone , key_name/group_name
      started = false
      while started == false
        sleep(5)
        res = @context[:ec2_api_handler].describe_instances(:instance_id => @context[:instance_id])
        state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
        @logger.info "instance in state #{state['name']} (#{state['code']})"
        if state['code'].to_i == 16
          started = true
          @context[:dns_name] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['dnsName']
          @context[:availability_zone] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['placement']['availabilityZone']
          @context[:kernel_id] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['kernelId']
          @context[:ramdisk_id] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['ramdiskId']
          @context[:architecture] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['architecture']
        elsif state['code'].to_i != 0
          raise Exception.new('instance failed to start up')
        end
      end
      AmiStarted.new(@context)
    end
  end

  # Ami started. Create a storage
  class AmiStarted < Ami2EbsConversionState
    def enter
      create_storage()
    end

    private

    def create_storage()
      @logger.debug "create volume in zone #{@context[:availability_zone]}"
      res = @context[:ec2_api_handler].create_volume(:availability_zone => @context[:availability_zone], :size => "10")
      @context[:volume_id] = res['volumeId']
      started = false
      while !started
        sleep(5)
        #TODO: check for timeout?
        res = @context[:ec2_api_handler].describe_volumes(:volume_id => @context[:volume_id])
        state = res['volumeSet']['item'][0]['status']
        @logger.debug "volume state #{state}"
        if state == 'available'
          started = true
        end
      end
      StorageCreated.new(@context)
    end

  end

  # Storage created. Attach it.
  class StorageCreated < Ami2EbsConversionState
    def enter
      attach_storage()
    end

    private

    def attach_storage()
      @logger.debug "attach volume #{@context[:volume_id]} to instance #{@context[:instance_id]} on device #{@context[:temp_device_name]}"
      @context[:ec2_api_handler].attach_volume(:volume_id => @context[:volume_id],
        :instance_id => @context[:instance_id],
        :device => @context[:temp_device_name]
      )
      done = false
      while !done
        sleep(5)
        #TODO: check for timeout?
        res = @context[:ec2_api_handler].describe_volumes(:volume_id => @context[:volume_id])
        state = res['volumeSet']['item'][0]['status']
        @logger.debug "storage attaching: #{state}"
        if  state == 'in-use'
          done = true
        end
      end
      StorageAttached.new(@context)
    end

  end

  # Storage attached. Create a file-system and moun it
  class StorageAttached < Ami2EbsConversionState
    def enter
      create_fs()
    end

    private

    def create_fs()
      @logger.debug "create filesystem on #{@context[:dns_name]} to #{@context[:temp_device_name]}"
      connect()
      @context[:remote_command_handler].create_filesystem("ext3", @context[:temp_device_name])
      FileSystemCreated.new(@context)
    end
  end

  # File system created. Mount it.
  class FileSystemCreated < Ami2EbsConversionState
    def enter
      mount_fs()
    end

    private

    def mount_fs()
      @context[:path] = "/mnt/tmp_#{@context[:volume_id]}"
      @logger.debug "mount #{@context[:temp_device_name]} on #{@context[:path]}"
      @context[:remote_command_handler].mkdir(@context[:path])
      @context[:remote_command_handler].mount(@context[:temp_device_name], @context[:path])
      sleep(2) #give mount some time
      if !@context[:remote_command_handler].drive_mounted?(@context[:path])
        raise Exception.new("drive #{@context[:path]} not mounted")
      end
      FileSystemMounted.new(@context)
    end
  end

  # File system created and mounted. Copy the root partition.
  class FileSystemMounted < Ami2EbsConversionState
    def enter
      copy()
    end

    private

    def copy()
      @logger.debug "start copying to #{@context[:path]}"
      start = Time.new.to_i
      @context[:remote_command_handler].rsync("/", "#{@context[:path]}", "/mnt/")
      @context[:remote_command_handler].rsync("/dev/", "#{@context[:path]}/dev/")
      endtime = Time.new.to_i
      @logger.info "copy took #{(endtime-start)}s"
      CopyDone.new(@context)
    end
  end
  
  # Copy operation done. Unmount volume.
  class CopyDone < Ami2EbsConversionState
    def enter
      unmount()
    end

    private

    def unmount()
      @logger.debug "unmount #{@context[:path]}"
      @context[:remote_command_handler].umount(@context[:path])
      sleep(2) #give umount some time
      if @context[:remote_command_handler].drive_mounted?(@context[:path])
        raise Exception.new("drive #{@context[:path]} not unmounted")
      end
      VolumeUnmounted.new(@context)
    end
  end

  # Volume unmounted. Detach it.
  class VolumeUnmounted < Ami2EbsConversionState
    def enter
      detach()
    end

    private

    def detach()
      @logger.debug "detach volume #{@context[:volume_id]}"
      @context[:ec2_api_handler].detach_volume(:volume_id => @context[:volume_id],
        :instance_id => @context[:instance_id]
      )
      done = false
      while !done
        sleep(3)
        #TODO: check for timeout?
        res = @context[:ec2_api_handler].describe_volumes(:volume_id => @context[:volume_id])
        @logger.debug "volume detaching: #{res.inspect}"
        if res['volumeSet']['item'][0]['status'] == 'available'
          done = true
        end
      end
      VolumeDetached.new(@context)
    end
  end


  # VolumeDetached. Create snaphot
  class VolumeDetached < Ami2EbsConversionState
    def enter
      create_snapshot()
    end

    private

    def create_snapshot()
      @logger.debug "create snapshot for volume #{@context[:volume_id]}"
      res = @context[:ec2_api_handler].create_snapshot(:volume_id => @context[:volume_id])
      @context[:snapshot_id] = res['snapshotId']
      @logger.info "snapshot_id = #{@context[:snapshot_id]}"
      done = false
      while !done
        sleep(5)
        #TODO: check for timeout?
        res = @context[:ec2_api_handler].describe_snapshots(:snapshot_id => @context[:snapshot_id])
        @logger.debug "snapshot creating: #{res.inspect}"
        if res['snapshotSet']['item'][0]['status'] == 'completed'
          done = true
        end
      end
      SnapshotCreated.new(@context)      
    end
  end

  # Snapshot created. Delete volume.
  class SnapshotCreated < Ami2EbsConversionState
    def enter
      delete_volume()
    end

    private

    def delete_volume
      @logger.debug "delete volume #{@context[:volume_id]}"
      res = @context[:ec2_api_handler].delete_volume(:volume_id => @context[:volume_id])
      VolumeDeleted.new(@context)
    end
  end

  # Volume deleted. Register snapshot.
  class VolumeDeleted < Ami2EbsConversionState
    def enter
      register()
    end

    private

    def register()
      @logger.debug "register snapshot #{@context[:snapshot_id]} as #{@context[:name]}"
      res = @context[:ec2_api_handler].register_image_updated(:snapshot_id => @context[:snapshot_id],
        :kernel_id => @context[:kernel_id], :architecture => @context[:architecture], 
        :root_device_name => @context[:root_device_name],
        :description => @context[:description], :name => @context[:name],
        :ramdisk_id => @context[:ramdisk_id]
      )
      @logger.debug "result of registration = #{res.inspect}"
      @context[:result][:image_id] = res['imageId']
      @logger.info "resulting image_id = #{@context[:result][:image_id]}"
      SnapshotRegistered.new(@context)
    end
  end

  # Snapshot registered. Shutdown instance.
  class SnapshotRegistered < Ami2EbsConversionState
    def enter
      shut_down()
    end

    private

    def shut_down()
      @logger.debug "shutdown instance #{@context[:instance_id]}"
      res = @context[:ec2_api_handler].terminate_instances(:instance_id => @context[:instance_id])
      done = false
      while done == false
        sleep(5)
        res = @context[:ec2_api_handler].describe_instances(:instance_id => @context[:instance_id])
        state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
        @logger.debug "instance in state #{state['name']} (#{state['code']})"
        if state['code'].to_i == 48
          done = true
        elsif state['code'].to_i != 32
          raise Exception.new('instance failed to shut down')
        end
      end
      Done.new(@context)      
    end
  end

  # Instance shutdown. Done.
  class Done < Ami2EbsConversionState
    def done?
      true
    end
  end
  
end
