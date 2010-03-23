# Contains methods that are used by the scripts in the state-machines. Since
# they are reused by different scripts, they are factored into this module.
# Parameters are read from the @context variable that must be defined. Results
# are written into @context[:result][...]
# Note: @context[:script] is set to a script object to pass information and messages
# to listeners
# Some other information might be expected in the @context object:
# * :remote_command_handler => ssh wrapper object
# * :ec2_api_handler => wrapper object around EC2 API access

module StateTransitionHelper

  # Connects to the remote host via SSH.
  # Params:
  # * dns_name => machine to connect to
  # * ssh_keyfile => key-file used for ssh
  # * ssh_keydata => contents of key-file (either use ssh_keyfile or ssh_keydata)
  def connect(dns_name, ssh_keyfile = nil, ssh_keydata = nil)
    @context[:script].post_message("connecting to #{dns_name}...")
    if @context[:remote_command_handler] == nil
      @context[:remote_command_handler] = RemoteCommandHandler.new
    end
    connected = false
    remaining_trials = 3
    while !connected && remaining_trials > 0
      remaining_trials -= 1
      if ssh_keyfile != nil
        begin
          @context[:remote_command_handler].connect_with_keyfile(dns_name, ssh_keyfile)
          connected = true
        rescue Exception => e
          @logger.info("connection failed due to #{e}")
          @logger.debug(e.backtrace.join("\n"))
        end
      elsif ssh_keydata != nil
        begin
          @context[:remote_command_handler].connect(dns_name, "root", ssh_keydata)
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
    @context[:script].post_message("connected to #{dns_name}. OS installed is #{@context[:result][:os]}")
    @logger.info "connected to #{dns_name}"
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
  def launch_instance(ami_id, key_name, security_group_name)
    @context[:script].post_message("starting up instance to execute the script (AMI = #{ami_id}) ...")
    @logger.debug "start up AMI #{ami_id}"
    # find out the image architecture first
    image_props = @context[:ec2_api_handler].describe_images(:image_id => ami_id)
    architecture = image_props['imagesSet']['item'][0]['architecture']
    instance_type = "m1.small"
    if architecture != "i386"
      instance_type = "m1.large"
    end
    arch_log_msg = "Architecture of image #{ami_id} is #{architecture}. Use instance_type #{instance_type}."
    @logger.info arch_log_msg
    @context[:script].post_message(arch_log_msg)
    # now start it
    res = @context[:ec2_api_handler].run_instances(:image_id => ami_id,
      :security_group => security_group_name, :key_name => key_name,
      :instance_type => instance_type
    )
    instance_id = res['instancesSet']['item'][0]['instanceId']
    @logger.info "started instance #{instance_id}"
    @context[:script].post_message("Started instance #{instance_id}. wait until it is ready...")
    #availability_zone , key_name/group_name
    started = false
    while started == false
      sleep(5)
      res = @context[:ec2_api_handler].describe_instances(:instance_id => instance_id)
      state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
      @logger.info "instance is in state #{state['name']} (#{state['code']})"
      if state['code'].to_i == 16
        started = true
        @context[:script].post_message("instance is up and running")
        dns_name = res['reservationSet']['item'][0]['instancesSet']['item'][0]['dnsName']
        availability_zone = res['reservationSet']['item'][0]['instancesSet']['item'][0]['placement']['availabilityZone']
        kernel_id = res['reservationSet']['item'][0]['instancesSet']['item'][0]['kernelId']
        ramdisk_id = res['reservationSet']['item'][0]['instancesSet']['item'][0]['ramdiskId']
        architecture = res['reservationSet']['item'][0]['instancesSet']['item'][0]['architecture']
      elsif state['code'].to_i != 0
        @context[:script].post_message("instance in state #{state['name']}")
        raise Exception.new('instance failed to start up')
      else
        @context[:script].post_message("instance still starting up...")
      end
    end
    return instance_id, dns_name, availability_zone, kernel_id, ramdisk_id, architecture
  end

  # Shuts down an instance.
  # Input Parameters:
  # * instance_id => ID of the instance to be shut down
  def shut_down_instance(instance_id)
    @context[:script].post_message("going to shut down the temporary instance #{instance_id}...")
    @logger.debug "shutdown instance #{instance_id}"
    res = @context[:ec2_api_handler].terminate_instances(:instance_id => instance_id)
    done = false
    while done == false
      sleep(5)
      res = @context[:ec2_api_handler].describe_instances(:instance_id => instance_id)
      state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
      @logger.debug "instance in state #{state['name']} (#{state['code']})"
      if state['code'].to_i == 48
        done = true
      elsif state['code'].to_i != 32
        raise Exception.new('instance failed to shut down')
      end
    end
    @context[:script].post_message("instance #{instance_id} is terminated")
  end

  # Creates a new EBS volume.
  # Input Parameters:
  # * availability_zone => availability zone for the volume
  # * size => size in Gigabytes
  # Returns
  # * volume_id => EC2 EBS Volume ID
  def create_volume(availability_zone, size = "10")
    @context[:script].post_message("going to create a new EBS volume...")
    @logger.debug "create volume in zone #{availability_zone}"
    res = @context[:ec2_api_handler].create_volume(:availability_zone => availability_zone, :size => size.to_s)
    volume_id = res['volumeId']
    started = false
    while !started
      sleep(5)
      #TODO: check for timeout?
      res = @context[:ec2_api_handler].describe_volumes(:volume_id => volume_id)
      state = res['volumeSet']['item'][0]['status']
      @logger.debug "volume state #{state}"
      if state == 'available'
        started = true
      end
    end
    @context[:script].post_message("EBS volume #{volume_id} is ready")
    return volume_id
  end

  # Creates a new EBS volume from a snapshot ID.
  # Input Parameters:
  # * availability_zone => availability zone for the volume
  # * size => size of the volume to be created
  # * snapshot_id => EC2 Snapshot ID used to create the volume
  # Returns
  # * volume_id => EC2 EBS Volume ID created
  def create_volume_from_snapshot(snapshot_id, availability_zone, size = "10")
    @context[:script].post_message("going to create a new EBS volume from the specified snapshot...")
    @logger.debug "create volume in zone #{availability_zone}"
    res = @context[:ec2_api_handler].create_volume(:snapshot_id => snapshot_id, :availability_zone => availability_zone, :size => size.to_s)
    volume_id = res['volumeId']
    started = false
    while !started
      sleep(5)
      #TODO: check for timeout?
      res = @context[:ec2_api_handler].describe_volumes(:volume_id => volume_id)
      state = res['volumeSet']['item'][0]['status']
      @logger.debug "volume state #{state}"
      if state == 'available'
        started = true
      end
    end
    @context[:script].post_message("EBS volume #{volume_id} is ready")
    return volume_id
  end

  # Attaches an EBS volume to an instance
  # Input Parameters:
  # * volume_id => EC2 ID for the EBS Volume to be attached
  # * instance_id => EC2 ID for the instance to which the volume is supposed to be attached to
  # * temp_device_name => device name to be used for attaching (e.g. /dev/sdj1)
  def attach_volume(volume_id, instance_id, temp_device_name)
    @context[:script].post_message("going to attach volume #{volume_id} to instance #{instance_id} on device #{temp_device_name}...")
    @logger.debug "attach volume #{volume_id} to instance #{instance_id} on device #{temp_device_name}"
    @context[:ec2_api_handler].attach_volume(:volume_id => volume_id,
      :instance_id => instance_id,
      :device => temp_device_name
    )
    done = false
    while !done
      sleep(5)
      #TODO: check for timeout?
      res = @context[:ec2_api_handler].describe_volumes(:volume_id => volume_id)
      state = res['volumeSet']['item'][0]['status']
      @logger.debug "storage attaching: #{state}"
      if  state == 'in-use'
        done = true
      end
    end
    @context[:script].post_message("volume successfully attached")
  end

  # Detach an EBS volume from an instance.
  # Input Parameters:
  # * volume_id => EC2 ID for the EBS Volume to be detached
  # * instance_id => EC2 ID for the instance to detach from
  def detach_volume(volume_id, instance_id)
    @context[:script].post_message("going to detach volume #{volume_id}...")
    @logger.debug "detach volume #{volume_id}"
    @context[:ec2_api_handler].detach_volume(:volume_id => volume_id,
      :instance_id => instance_id
    )
    done = false
    while !done
      sleep(3)
      #TODO: check for timeout?
      res = @context[:ec2_api_handler].describe_volumes(:volume_id => volume_id)
      @logger.debug "volume detaching: #{res.inspect}"
      if res['volumeSet']['item'][0]['status'] == 'available'
        done = true
      end
    end
    @context[:script].post_message("volume #{volume_id} detached.")
  end

  # Delete an EBS volume.
  # Input Parameters:
  # * volume_id => EC2 ID for the EBS Volume to be deleted
  def delete_volume(volume_id)
    @context[:script].post_message("going to delete volume #{volume_id} (no longer needed)...")
    @logger.debug "delete volume #{volume_id}"
    @context[:ec2_api_handler].delete_volume(:volume_id => volume_id)
    @context[:script].post_message("volume #{volume_id} deleted")
  end

  # Creates a snapshot for an EBS volume.
  # Input Parameters::
  # * volume_id => EC2 ID for the EBS volume to be snapshotted
  # Returns:
  # * snapshot_id => EC2 ID for the snapshot created
  def create_snapshot(volume_id)
    @context[:script].post_message("going to create a snapshot for volume #{volume_id}...")
    @logger.debug "create snapshot for volume #{volume_id}"
    res = @context[:ec2_api_handler].create_snapshot(:volume_id => volume_id)
    snapshot_id = res['snapshotId']
    @logger.info "snapshot_id = #{snapshot_id}"
    done = false
    while !done
      sleep(5)
      #TODO: check for timeout?
      res = @context[:ec2_api_handler].describe_snapshots(:snapshot_id => snapshot_id)
      @logger.debug "snapshot creating: #{res.inspect}"
      if res['snapshotSet']['item'][0]['status'] == 'completed'
        done = true
      end
    end
    @context[:script].post_message("snapshot is done with ID=#{snapshot_id}")
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
    @context[:script].post_message("going to register snapshot #{snapshot_id}...")
    @logger.debug "register snapshot #{snapshot_id} as #{name}"
    res = @context[:ec2_api_handler].register_image_updated(:snapshot_id => snapshot_id,
      :kernel_id => kernel_id, :architecture => architecture,
      :root_device_name => root_device_name,
      :description => description, :name => name,
      :ramdisk_id => ramdisk_id
    )
    @logger.debug "result of registration = #{res.inspect}"
    image_id = res['imageId']
    @logger.info "resulting image_id = #{image_id}"
    @context[:script].post_message("snapshot #{snapshot_id} successfully registered as AMI #{image_id} ")
    return image_id
  end

  # Create a file-system on a given machine (assumes to be connected already).
  # Input Parameters:
  # * dns_name => IP used
  # * device => device to be used for file-system creation (e.g. /dev/sdj)
  def create_fs(dns_name, device)
    @context[:script].post_message("going to create filesystem on #{dns_name} to #{device}...")
    @logger.debug "create filesystem on #{dns_name} to #{device}"
    @context[:remote_command_handler].create_filesystem("ext3", device)
    @context[:script].post_message("filesystem system successfully created")
  end

  # Create a file-system on a given machine (assumes to be connected already).
  # Input Parameters:
  # * mount_point => directory to be mounted on the device
  # * device => device used for mounting
  def mount_fs(mount_point, device)
    @context[:script].post_message("going to mount #{device} on #{mount_point}...")
    @logger.debug "mount #{device} on #{mount_point}"
    @context[:remote_command_handler].mkdir(mount_point)
    @context[:remote_command_handler].mount(device, mount_point)
    sleep(2) #give mount some time
    if !@context[:remote_command_handler].drive_mounted?(mount_point)
      raise Exception.new("drive #{mount_point} not mounted")
    end
    @context[:script].post_message("mount successful")
  end

  # Unmount a drive
  # Input Parameters:
  # * mount_point => directory to be unmounted
  def unmount_fs(mount_point)
    @context[:script].post_message("Going to unmount ...")
    @logger.debug "unmount #{mount_point}"
    @context[:remote_command_handler].umount(mount_point)
    sleep(2) #give umount some time
    if @context[:remote_command_handler].drive_mounted?(mount_point)
      raise Exception.new("drive #{mount_point} not unmounted")
    end
    @context[:script].post_message("device unmounted")
  end

  # Copy all files of a running linux distribution via rsync to a mounted directory
  # Input Parameters:
  # * destination_path => where to copy to
  def copy_distribution(destination_path)
    @context[:script].post_message("going to start copying files to #{destination_path}. This may take quite a time...")
    @logger.debug "start copying to #{destination_path}"
    start = Time.new.to_i
    @context[:remote_command_handler].rsync("/", "#{destination_path}", "#{destination_path}")
    @context[:remote_command_handler].rsync("/dev/", "#{destination_path}/dev/")
    endtime = Time.new.to_i
    @logger.info "copy took #{(endtime-start)}s"
    @context[:script].post_message("copying is done (took #{endtime-start})s")
  end

  # Zips all files on a mounted-directory into a file
  # Input Parameters:
  # * source_dir => where to copy from
  # * zip_file_dest => path where the zip-file should be stored
  # # zip_file_name => name of the zip file (without .zip suffix)
  def zip_volume(source_dir, zip_file_dest, zip_file_name)
    @context[:script].post_message("going to zip the EBS volume")
    @context[:remote_command_handler].zip(source_dir, zip_file_dest+zip_file_name)
    @context[:script].post_message("EBS volume successfully zipped")
  end

end
