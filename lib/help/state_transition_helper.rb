require 'net/scp'

# Contains methods that are used by the scripts in the state-machines. Since
# they are reused by different scripts, they are factored into this module.
#
# Note: it is supposed that a hash named @context exists @context[:script]
# must be set to a script object to pass information and messages
# to listeners.
# Some other information is expected to be provided in the @context object:
# * :remote_command_handler => ssh wrapper object
# * :ec2_api_handler => wrapper object around EC2 API access

module StateTransitionHelper

  # Connects to the remote host via SSH.
  # Params:
  # * dns_name => machine to connect to
  # * ssh_keyfile => key-file used for ssh
  # * ssh_keydata => contents of key-file (either use ssh_keyfile or ssh_keydata)
  # Returns:
  # * OS of the connected machine
  def connect(dns_name, ssh_keyfile = nil, ssh_keydata = nil)
    post_message("connecting to #{dns_name}...")
    connected = false
    last_connection_problem = ""
    remaining_trials = 5
    while !connected && remaining_trials > 0
      remaining_trials -= 1
      if ssh_keyfile != nil
        begin
          @logger.info("connecting using keyfile")
          remote_handler().connect_with_keyfile(dns_name, ssh_keyfile)
          connected = true
        rescue Exception => e
          @logger.info("connection failed due to #{e}")
          last_connection_problem = "#{e}"
          @logger.debug(e.backtrace.select(){|line| line.include?("state_transition_helper")}.join("\n"))
        end
      elsif ssh_keydata != nil
        begin
          @logger.info("connecting using keydata")
          remote_handler().connect(dns_name, "root", ssh_keydata)
          connected = true
        rescue Exception => e
          @logger.info("connection failed due to #{e}")
          last_connection_problem = "#{e}"
          @logger.debug(e.backtrace.select(){|line| line.include?("state_transition_helper")}.join("\n"))
        end
      else
        raise Exception.new("no key information specified")
      end
      if !connected
        sleep(20) #try again
      end
    end
    if !connected
      raise Exception.new("connection attempts stopped (#{last_connection_problem})")
    end
    os = remote_handler().retrieve_os()
    post_message("connected to #{dns_name}. OS installed is #{os}")
    @logger.info "connected to #{dns_name}"
    return os
  end

  # If a remote command handler is connected, disconnect him silently.
  def disconnect
    begin
      remote_handler().disconnect()
    rescue
    end
    self.remote_handler= nil
  end

  # Launch an instance based on an AMI ID
  # Input Parameters:
  # * ami_id => ID of the AMI to be launched
  # * key_name => name of the key to access the instance
  # * security_group_name => name of the security group to be used
  # Returned information:
  # * instance_id => ID of the started instance
  # * dns_name => DNS name of the started instance
  # * availability_zone => Availability zone of the started instance
  # * kernel_id => EC2 Kernel ID of the started instance
  # * ramdisk_id => EC2 Ramdisk ID of the started instance
  # * architecture => architecture (e.g. 386i, 64x) of the started instance
  def launch_instance(ami_id, key_name, security_group_name, ec2_handler = nil)
    ec2_handler = ec2_handler() if ec2_handler == nil
    post_message("starting up instance to execute the script (AMI = #{ami_id}) ...")
    @logger.debug "start up AMI #{ami_id}"
    # find out the image architecture first
    image_props = ec2_handler.describe_images(:image_id => ami_id)
    architecture = image_props['imagesSet']['item'][0]['architecture']
    instance_type = "m1.small"
    if architecture != "i386"
      instance_type = "m1.large"
    end
    arch_log_msg = "Architecture of image #{ami_id} is #{architecture}. Use instance_type #{instance_type}."
    @logger.info arch_log_msg
    post_message(arch_log_msg)
    # now start it
    res = ec2_handler.run_instances(:image_id => ami_id,
      :security_group => security_group_name, :key_name => key_name,
      :instance_type => instance_type
    )
    instance_id = res['instancesSet']['item'][0]['instanceId']
    @logger.info "started instance #{instance_id}"
    post_message("Started instance #{instance_id}. wait until it is ready...")
    #availability_zone , key_name/group_name
    started = false
    while started == false
      sleep(5)
      res = ec2_handler.describe_instances(:instance_id => instance_id)
      state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
      @logger.info "instance is in state #{state['name']} (#{state['code']})"
      if state['code'].to_i == 16
        started = true
        post_message("instance is up and running")
        dns_name = res['reservationSet']['item'][0]['instancesSet']['item'][0]['dnsName']
        availability_zone = res['reservationSet']['item'][0]['instancesSet']['item'][0]['placement']['availabilityZone']
        kernel_id = res['reservationSet']['item'][0]['instancesSet']['item'][0]['kernelId']
        ramdisk_id = res['reservationSet']['item'][0]['instancesSet']['item'][0]['ramdiskId']
        architecture = res['reservationSet']['item'][0]['instancesSet']['item'][0]['architecture']
      elsif state['code'].to_i != 0
        post_message("instance in state #{state['name']}")
        raise Exception.new('instance failed to start up')
      else
        post_message("instance still starting up...")
      end
    end
    return instance_id, dns_name, availability_zone, kernel_id, ramdisk_id, architecture
  end

  # Shuts down an instance.
  # Input Parameters:
  # * instance_id => ID of the instance to be shut down
  def shut_down_instance(instance_id)
    post_message("going to shut down the temporary instance #{instance_id}...")
    @logger.debug "shutdown instance #{instance_id}"
    res = ec2_handler().terminate_instances(:instance_id => instance_id)
    done = false
    while done == false
      sleep(5)
      res = ec2_handler().describe_instances(:instance_id => instance_id)
      state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
      @logger.debug "instance in state #{state['name']} (#{state['code']})"
      if state['code'].to_i == 48
        done = true
      elsif state['code'].to_i != 32
        raise Exception.new('instance failed to shut down')
      end
    end
    post_message("instance #{instance_id} is terminated")
  end

  # Creates a new EBS volume.
  # Input Parameters:
  # * availability_zone => availability zone for the volume
  # * size => size in Gigabytes
  # Returns
  # * volume_id => EC2 EBS Volume ID
  def create_volume(availability_zone, size = "10")
    post_message("going to create a new EBS volume of size #{size}GB...")
    @logger.debug "create volume in zone #{availability_zone}"
    res = ec2_handler().create_volume(:availability_zone => availability_zone, :size => size.to_s)
    volume_id = res['volumeId']
    started = false
    while !started
      sleep(5)
      #TODO: check for timeout?
      res = ec2_handler().describe_volumes(:volume_id => volume_id)
      state = res['volumeSet']['item'][0]['status']
      @logger.debug "volume state #{state}"
      if state == 'available'
        started = true
      end
    end
    post_message("EBS volume #{volume_id} is ready")
    return volume_id
  end

  # Creates a new EBS volume from a snapshot ID.
  # Input Parameters:
  # * availability_zone => availability zone for the volume
  # * size => size of the volume to be created
  # * snapshot_id => EC2 Snapshot ID used to create the volume
  # Returns
  # * volume_id => EC2 EBS Volume ID created
  def create_volume_from_snapshot(snapshot_id, availability_zone)
    post_message("going to create a new EBS volume from the specified snapshot...")
    @logger.debug "create volume in zone #{availability_zone}"
    res = ec2_handler().create_volume(:snapshot_id => snapshot_id, :availability_zone => availability_zone)
    volume_id = res['volumeId']
    started = false
    while !started
      sleep(5)
      #TODO: check for timeout?
      res = ec2_handler().describe_volumes(:volume_id => volume_id)
      state = res['volumeSet']['item'][0]['status']
      @logger.debug "volume state #{state}"
      if state == 'available'
        started = true
      end
    end
    post_message("EBS volume #{volume_id} is ready")
    return volume_id
  end

  # Attaches an EBS volume to an instance
  # Input Parameters:
  # * volume_id => EC2 ID for the EBS Volume to be attached
  # * instance_id => EC2 ID for the instance to which the volume is supposed to be attached to
  # * temp_device_name => device name to be used for attaching (e.g. /dev/sdj1)
  def attach_volume(volume_id, instance_id, temp_device_name)
    post_message("going to attach volume #{volume_id} to instance #{instance_id} on device #{temp_device_name}...")
    @logger.debug "attach volume #{volume_id} to instance #{instance_id} on device #{temp_device_name}"
    ec2_handler().attach_volume(:volume_id => volume_id,
      :instance_id => instance_id,
      :device => temp_device_name
    )
    done = false
    while !done
      sleep(5)
      #TODO: check for timeout?
      res = ec2_handler().describe_volumes(:volume_id => volume_id)
      state = res['volumeSet']['item'][0]['status']
      @logger.debug "storage attaching: #{state}"
      if  state == 'in-use'
        done = true
      end
    end
    post_message("volume successfully attached")
  end

  # Detach an EBS volume from an instance.
  # Input Parameters:
  # * volume_id => EC2 ID for the EBS Volume to be detached
  # * instance_id => EC2 ID for the instance to detach from
  def detach_volume(volume_id, instance_id)
    post_message("going to detach volume #{volume_id}...")
    @logger.debug "detach volume #{volume_id}"
    ec2_handler().detach_volume(:volume_id => volume_id,
      :instance_id => instance_id
    )
    done = false
    while !done
      sleep(3)
      #TODO: check for timeout?
      res = ec2_handler().describe_volumes(:volume_id => volume_id)
      @logger.debug "volume detaching: #{res.inspect}"
      if res['volumeSet']['item'][0]['status'] == 'available'
        done = true
      end
    end
    post_message("volume #{volume_id} detached.")
  end

  # Delete an EBS volume.
  # Input Parameters:
  # * volume_id => EC2 ID for the EBS Volume to be deleted
  def delete_volume(volume_id)
    post_message("going to delete volume #{volume_id} (no longer needed)...")
    @logger.debug "delete volume #{volume_id}"
    ec2_handler().delete_volume(:volume_id => volume_id)
    post_message("volume #{volume_id} deleted")
  end

  # Creates a snapshot for an EBS volume.
  # Input Parameters::
  # * volume_id => EC2 ID for the EBS volume to be snapshotted
  # Returns:
  # * snapshot_id => EC2 ID for the snapshot created
  def create_snapshot(volume_id, description = "")
    post_message("going to create a snapshot for volume #{volume_id}...")
    @logger.debug "create snapshot for volume #{volume_id}"
    res = ec2_handler().create_snapshot(:volume_id => volume_id,
      :description => description)
    snapshot_id = res['snapshotId']
    @logger.info "snapshot_id = #{snapshot_id}"
    done = false
    while !done
      sleep(5)
      #TODO: check for timeout?
      res = ec2_handler().describe_snapshots(:snapshot_id => snapshot_id)
      @logger.debug "snapshot creating: #{res.inspect}"
      if res['snapshotSet']['item'][0]['status'] == 'completed'
        done = true
      end
    end
    post_message("snapshot is done with ID=#{snapshot_id}")
    return snapshot_id
  end

  # Registers a snapshot as EBS-booted AMI.
  # Input Parameters:
  # * snapshot_id => EC2 Snapshot ID used to be used
  # * name => name of the AMI to be created
  # * root_device_name => Root device name (e.g. /dev/sdj) to be used for AMI registration
  # * description => description of the AMI to be created
  # * kernel_id => EC2 Kernel ID to be used for AMI registration
  # * ramdisk_id => EC2 Ramdisk ID to be used for AMI registration
  # * architecture => architecture (e.g. 386i, 64x) to be used for AMI registration
  # Returns:
  # * image_id => ID of the AMI created and registered
  def register_snapshot(snapshot_id, name, root_device_name, description, kernel_id, ramdisk_id, architecture)
    post_message("going to register snapshot #{snapshot_id}...")
    @logger.debug "register snapshot #{snapshot_id} as #{name}"
    res = ec2_handler().register_image_updated(:snapshot_id => snapshot_id,
      :kernel_id => kernel_id, :architecture => architecture,
      :root_device_name => root_device_name,
      :description => description, :name => name,
      :ramdisk_id => ramdisk_id
    )
    @logger.debug "result of registration = #{res.inspect}"
    image_id = res['imageId']
    @logger.info "resulting image_id = #{image_id}"
    post_message("snapshot #{snapshot_id} successfully registered as AMI #{image_id} ")
    return image_id
  end

  # Create a file-system on a given machine (assumes to be connected already).
  # Input Parameters:
  # * dns_name => IP used
  # * device => device to be used for file-system creation (e.g. /dev/sdj)
  def create_fs(dns_name, device)
    post_message("going to create filesystem on #{dns_name} to #{device}...")
    @logger.debug "create filesystem on #{dns_name} to #{device}"
    remote_handler().create_filesystem("ext3", device)
    post_message("filesystem system successfully created")
  end

  # Create a file-system on a given machine (assumes to be connected already).
  # Input Parameters:
  # * mount_point => directory to be mounted on the device
  # * device => device used for mounting
  def mount_fs(mount_point, device)
    post_message("going to mount #{device} on #{mount_point}...")
    @logger.debug "mount #{device} on #{mount_point}"
    if !remote_handler.file_exists?(mount_point)
      remote_handler().mkdir(mount_point)
    end
    remote_handler().mount(device, mount_point)
    trials = 3
    mounted = false
    while trials > 0
      sleep(5) #give mount some time
      if remote_handler().drive_mounted?(mount_point)
        mounted = true
        break
      end
      trials -= trials
    end
    if !mounted
      raise Exception.new("drive #{mount_point} not mounted")
    end
    post_message("mount successful")
  end

  # Unmount a drive
  # Input Parameters:
  # * mount_point => directory to be unmounted
  def unmount_fs(mount_point)
    post_message("Going to unmount ...")
    @logger.debug "unmount #{mount_point}"
    remote_handler().umount(mount_point)
    sleep(2) #give umount some time
    if remote_handler().drive_mounted?(mount_point)
      raise Exception.new("drive #{mount_point} not unmounted")
    end
    post_message("device unmounted")
  end

  # Copy all files of a running linux distribution via rsync to a mounted directory
  # Input Parameters:
  # * destination_path => where to copy to
  def copy_distribution(destination_path)
    post_message("going to start copying files to #{destination_path}. This may take quite a time...")
    @logger.debug "start copying to #{destination_path}"
    start = Time.new.to_i
    remote_handler().local_rsync("/", "#{destination_path}", "#{destination_path}")
    remote_handler().local_rsync("/dev/", "#{destination_path}/dev/")
    endtime = Time.new.to_i
    @logger.info "copy took #{(endtime-start)}s"
    post_message("copying is done (took #{endtime-start})s")
  end

  # Zips all files on a mounted-directory into a file
  # Input Parameters:
  # * source_dir => where to copy from
  # * zip_file_dest => path where the zip-file should be stored
  # # zip_file_name => name of the zip file (without .zip suffix)
  def zip_volume(source_dir, zip_file_dest, zip_file_name)
    post_message("going to zip the EBS volume")
    remote_handler().zip(source_dir, zip_file_dest+"/"+zip_file_name)
    post_message("EBS volume successfully zipped")
  end

  def remote_copy(keyname, source_dir, dest_machine, dest_dir)
    post_message("going to remote copy all files from volume. This may take some time...")
    remote_handler().remote_rsync("/root/.ssh/#{keyname}.pem", source_dir, dest_machine, dest_dir)
    post_message("remote copy operation done")
  end

  def upload_file(ip, user, key_data, file, target_file)
    post_message("going to upload #{file} to #{ip}:/#{target_file}")
    remote_handler().upload(ip, user, key_data, file, target_file)
  end

  #setting/retrieving handlers

  def remote_handler()
    if @remote_handler == nil
      if @context[:remote_command_handler] == nil
        @context[:remote_command_handler] = RemoteCommandHandler.new
      else
        @remote_handler = @context[:remote_command_handler]
      end
    end
    @remote_handler
  end

  def remote_handler=(remote_handler)
    @remote_handler = remote_handler
  end

  def ec2_handler()
    if @ec2_handler == nil
      @ec2_handler = @context[:ec2_api_handler]
    end
    @ec2_handler
  end

  def ec2_handler=(ec2_handler)
    @ec2_handler = ec2_handler
  end


  protected

  def post_message(msg)
    if @context[:script] != nil
      @context[:script].post_message(msg)
    end
  end

end
