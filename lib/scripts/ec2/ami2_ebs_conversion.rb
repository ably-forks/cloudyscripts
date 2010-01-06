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
  
  def initialize(input_params)
    super(input_params)
    @result = {:done => false}
  end

  # Executes the script.
  def start_script()
    begin
      # optional parameters and initialization
      # TODO
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
      puts "exception during encryption: #{e}"
      puts e.backtrace.join("\n")
      err = e.to_s
      err += " (in #{current_state.end_state.to_s})" unless current_state == nil
      @result[:failed] = true
      @result[:failure_reason] = err
      @result[:end_state] = current_state.end_state unless current_state == nil
    ensure
      begin
      @input_params[:remote_command_handler].disconnect
      rescue Exception => e2
        #puts "rescue disconnect: #{e2}"
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
      context[:device] = "/dev/sdj" #TODO: count up? input parameter?
      state = context[:initial_state] == nil ? InitialState.new(context) : context[:initial_state]
      state
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
      res = @context[:ec2_api_handler].run_instances(:image_id => @context[:ami_id], 
        :security_group => @context[:security_group_name], :key_name => @context[:key_name])
      instance_id = res['instancesSet']['item'][0]['instanceId']
      @context[:instance_id] = instance_id
      puts "res = #{res.inspect}"
      #availability_zone , key_name/group_name
      started = false
      while started == false
        sleep(5)
        res = @context[:ec2_api_handler].describe_instances(:instance_id => @context[:instance_id])
        puts "describe_instances = #{res.inspect}"
        state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
        puts "instance in state #{state['name']} (#{state['code']})"
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
      res = @context[:ec2_api_handler].create_volume(:availability_zone => @context[:availability_zone], :size => "10")
      @context[:volume_id] = res['volumeId']
      started = false
      while !started
        sleep(5)
        #TODO: check for timeout?
        res = @context[:ec2_api_handler].describe_volumes(:volume_id => @context[:volume_id])
        puts "res = #{res.inspect}"
        if res['volumeSet']['item'][0]['status'] == 'available'
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
      @context[:ec2_api_handler].attach_volume(:volume_id => @context[:volume_id],
        :instance_id => @context[:instance_id],
        :device => @context[:device]
      )
      started = false
      while !started
        sleep(5)
        #TODO: check for timeout?
        res = @context[:ec2_api_handler].describe_volumes(:volume_id => @context[:volume_id])
        puts "res = #{res.inspect}"
        if res['volumeSet']['item'][0]['status'] == 'in-use'
          started = true
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
      if @context[:remote_command_handler] == nil
        @context[:remote_command_handler] = RemoteCommandHandler.new
      end
      if @context[:ssh_keyfile] != nil
        puts @context[:remote_command_handler].inspect
        @context[:remote_command_handler].connect_with_keyfile(@context[:dns_name], @context[:ssh_keyfile])
      elsif @context[:ssh_keydata] != nil
        @context[:remote_command_handler].connect(@context[:dns_name], "root", @context[:ssh_keydata])
      else
        raise Exception.new("no key information specified")
      end
      puts "connected"
      @context[:remote_command_handler].create_filesystem("ext3", @context[:device])
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
      @context[:remote_command_handler].mkdir(@context[:path])
      @context[:remote_command_handler].mount(@context[:device], @context[:path])
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
      start = Time.new.to_i
      @context[:remote_command_handler].rsync("/", "#{@context[:path]}")
      @context[:remote_command_handler].rsync("/dev/", "#{@context[:path]}/dev/")
      endtime = Time.new.to_i
      puts "copy took #{(endtime-start)}s"
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
      @context[:ec2_api_handler].detach_volume(:volume_id => @context[:volume_id],
        :instance_id => @context[:instance_id]
      )
      done = false
      while !done
        sleep(3)
        #TODO: check for timeout?
        res = @context[:ec2_api_handler].describe_volumes(:volume_id => @context[:volume_id])
        puts "res = #{res.inspect}"
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
      res = @context[:ec2_api_handler].create_snapshot(:volume_id => @context[:volume_id])
      @context[:snapshot_id] = res['snapshotId']
      puts "snapshot_id = #{@context[:snapshot_id]}"
      done = false
      while !done
        sleep(5)
        #TODO: check for timeout?
        res = @context[:ec2_api_handler].describe_snapshots(:snapshot_id => @context[:snapshot_id])
        puts "res = #{res.inspect}"
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
      res = @context[:ec2_api_handler].delete_volume(:volume_id => @context[:volume_id])
      puts "delete volume: result = #{res}"
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
      res = @context[:ec2_api_handler].register_image_updated(:snapshot_id => @context[:snapshot_id],
        :kernel_id => @context[:kernel_id], :architecture => @context[:architecture], :root_device_name => "/dev/sda1",
        :description => "Good description!", :name => "Complete Run (#{@context[:instance_id]})", :ramdisk_id => @context[:ramdisk_id]
      ) #TODO: name, description, root-device-name
      puts "result of registration = #{res.inspect}"
      @context[:image_id] = res['imageId']
      puts "resulting image_id = #{@context[:image_id]}"
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
      res = @context[:ec2_api_handler].terminate_instances(:instance_id => @context[:instance_id])
      done = false
      while done == false
        sleep(5)
        res = @context[:ec2_api_handler].describe_instances(:instance_id => @context[:instance_id])
        puts "describe_instances = #{res.inspect}"
        state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
        puts "instance in state #{state['name']} (#{state['code']})"
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

  
  # Use an instance in the same region as your image to do the following,
  #    from http://coderslike.us/2009/12/07/amazon-ec2-boot-from-ebs-and-ami-conversion/
  #    * download the image bundle to the ephemeral store: ec2-download-bundle
  #    * unbundle the image (resulting in a single file): ec2-unbundle
  #    * create a temporary EBS volume in the same availability zone as the instance
  #    * attach the volume to your instance
  #    * copy the unbundled image onto the raw EBS volume
  #    * mount the EBS volume
  #    * edit /etc/fstab on the volume to remove the ephemeral store mount line
  #    * unmount and detach the volume
  #    * create a snapshot of the EBS volume
  #    * register the snapshot as an image, and you’re done!

end
