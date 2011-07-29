require 'net/scp'
require "AWS"

# Contains methods that are used by the scripts in the state-machines. Since
# they are reused by different scripts, they are factored into this module.
#
# Note: it is supposed that a hash named @context exists @context[:script]
# must be set to a script object to pass information and messages
# to listeners.
# Some other information is expected to be provided in the @context object:
# * :remote_command_handler => ssh wrapper object
# * :ec2_api_handler => wrapper object around EC2 API access

class AWS::EC2::Base
  def register_image_updated(options)
    puts "register_iamge_updated: #{options.inspect}"
    params = {}
    params["Name"] = options[:name].to_s
    params["BlockDeviceMapping.1.Ebs.SnapshotId"] = options[:snapshot_id].to_s
    params["BlockDeviceMapping.1.DeviceName"] = options[:root_device_name].to_s
    params["Description"] = options[:description].to_s
    params["KernelId"] = options[:kernel_id].to_s unless options[:kernel_id] == nil
    params["RamdiskId"] = options[:ramdisk_id].to_s unless options[:ramdisk_id] == nil
    params["Architecture"] = options[:architecture].to_s
    params["RootDeviceName"] = options[:root_device_name].to_s
    return response_generator(:action => "RegisterImage", :params => params)
  end
end

module StateTransitionHelper

  # Connects to the remote host via SSH.
  # Params:
  # * dns_name => machine to connect to
  # * user_name => name to be used for connection
  # * ssh_keyfile => key-file used for ssh
  # * ssh_keydata => contents of key-file (either use ssh_keyfile or ssh_keydata)
  # Returns:
  # * OS of the connected machine
  def connect(dns_name, user_name, ssh_keyfile = nil, ssh_keydata = nil,
      trials = 5, wait_between_trials = 20)
    post_message("connecting '#{user_name}' to #{dns_name}...")
    connected = false
    last_connection_problem = ""
    remaining_trials = trials-1
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
          remote_handler().connect(dns_name, user_name, ssh_keydata)
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
        sleep(wait_between_trials) #try again
      end
    end
    if !connected
      raise Exception.new("connection attempts stopped (#{last_connection_problem})")
    end
    os = remote_handler().retrieve_os()
    sudo = remote_handler().use_sudo ? " [sudo]" : ""
    post_message("connected to #{dns_name}#{sudo}. OS installed is #{os}")
    @logger.info "connected to #{dns_name}#{sudo}"
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
  # * type => type of instance to start
  # Returned information:
  # * instance_id => ID of the started instance
  # * dns_name => DNS name of the started instance
  # * availability_zone => Availability zone of the started instance
  # * kernel_id => EC2 Kernel ID of the started instance
  # * ramdisk_id => EC2 Ramdisk ID of the started instance
  # * architecture => architecture (e.g. 386i, 64x) of the started instance
  def launch_instance(ami_id, key_name, security_group_name, ec2_handler = nil, type = nil)
    ec2_handler = ec2_handler() if ec2_handler == nil
    post_message("starting up instance to execute the script (AMI = #{ami_id}) ...")
    @logger.debug "start up AMI #{ami_id}"
    # find out the image architecture first
    image_props = ec2_handler.describe_images(:image_id => ami_id)
    architecture = image_props['imagesSet']['item'][0]['architecture']
    instance_type = "m1.small"
    #instance_type = "t1.micro"
    if architecture != "i386"
      instance_type = "m1.large"
    end
    instance_type = type if type != nil
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

  # Start an instance
  # Input Paramters:
  # * instance_id => ID of the instance to start
  # * timeout => a timeout for waiting instance to start to avoid infinite loop (default set to 4m)
  # Return Parameters (Array):
  # * instance_id
  # * public_dns_name
  def start_instance(instance_id, timeout = 240)
    dns_name = ""
    post_message("going to start instance '#{instance_id}'...")
    res = ec2_handler().describe_instances(:instance_id => instance_id)
    state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
    if state['code'].to_i == 16
      dns_name = res['reservationSet']['item'][0]['instancesSet']['item'][0]['dnsName'] 
      msg = "instance '#{instance_id}' already started"
      @logger.warn "#{msg}"
      post_message("#{msg}")
      done = true
    else
      @logger.debug "start instance #{instance_id}"
      ec2_handler().start_instances(:instance_id => instance_id)
    end
      while timeout > 0 && !done
      res = ec2_handler().describe_instances(:instance_id => instance_id)
      state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
      @logger.debug "instance in state '#{state['name']}' (#{state['code']})"
      if state['code'].to_i == 16 
        done = true
        timeout = 0
        dns_name = res['reservationSet']['item'][0]['instancesSet']['item'][0]['dnsName']
      elsif state['code'].to_i != 0 
        done = false
        timeout = 0
        msg = "instance in state '#{state['name']}'"
        @logger.error "#{msg}"
        post_message("#{msg}")
      end
      sleep(5)
      timeout -= 5
    end
    msg = ""
    if !done
      msg = "Failed to start instance '#{instance_id}"
      @logger.error "#{msg}"
      raise Exception.new("Unable to start instance '#{instance_id}'}")
    else
      msg = "'#{instance_id}' successfully started" 
      @logger.info "#{msg}" 
    end
    post_message("#{msg}")
    return instance_id, dns_name
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

  def retrieve_security_groups()
    @context[:script].post_message("going to retrieve security groups...")
    sgs = @context[:ec2_api_handler].describe_security_groups()
    @context[:script].post_message("found #{sgs.size} security groups")
    @logger.info("found #{sgs.size} security groups")
    @context[:security_groups] = sgs
  end

  def retrieve_instances()
    @context[:script].post_message("going to retrieve all instances...")
    inst = @context[:ec2_api_handler].describe_instances()
    @context[:script].post_message("found #{inst.size} instances")
    @logger.info("found #{inst.size} instances")
    @context[:ec2_instances] = inst
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
    @logger.info "attach volume #{volume_id} to instance #{instance_id} on device #{temp_device_name}"
    ec2_handler().attach_volume(:volume_id => volume_id,
      :instance_id => instance_id,
      :device => temp_device_name
    )
    done = false
    timeout = 120
    while timeout > 0
      res = ec2_handler().describe_volumes(:volume_id => volume_id)
      vol_state = res['volumeSet']['item'][0]['status']
      attachment_state = res['volumeSet']['item'][0]['attachmentSet']['item'][0]['status']
      @logger.debug "storage attaching: volume state: #{vol_state}, attachment state: #{attachment_state}"
      if vol_state == 'in-use' && attachment_state == 'attached' 
        done = true
        timeout = 0
      end
      sleep(5)
      timeout -= 5
    end
    msg = ""
    if !done
      msg = "Failed to attach volume '#{volume_id}' to instance '#{instance_id}"
      @logger.error "#{msg}"
      raise Exception.new("volume #{mount_point} not attached")
    else
      msg = "volume #{volume_id} successfully attached" 
      @logger.info "#{msg}"
    end
    post_message("#{msg}")
  end

  # Detach an EBS volume from an instance.
  # Input Parameters:
  # * volume_id => EC2 ID for the EBS Volume to be detached
  # * instance_id => EC2 ID for the instance to detach from
  def detach_volume(volume_id, instance_id)
    post_message("going to detach volume #{volume_id} from instance #{instance_id}...")
    @logger.info "detach volume #{volume_id} from instance #{instance_id}"
    ec2_handler().detach_volume(:volume_id => volume_id,
      :instance_id => instance_id
    )
    done = false
    timeout = 120
    while timeout > 0
      sleep(3)
      res = ec2_handler().describe_volumes(:volume_id => volume_id)
      @logger.debug "volume detaching: #{res.inspect}"
      if res['volumeSet']['item'][0]['status'] == 'available'
        done = true
        timeout = 0
      end
      sleep(5)
      timeout -= 5
    end
    msg = ""
    if !done
      msg = "Failed to detach volume '#{volume_id}' from instance '#{instance_id}"
      @logger.error "#{msg}"
      raise Exception.new("volume #{mount_point} not detached")
    else
      msg = "volume #{volume_id} successfully detached" 
      @logger.info "#{msg}"
    end
    post_message("#{msg}")
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

  # Deletes a snapshot.
  def delete_snapshot(snapshot_id)
    post_message("going to delete snapshot #{snapshot_id}...")
    @logger.info("going to delete snapshot #{snapshot_id}...")
    ec2_handler().delete_snapshot(:snapshot_id => snapshot_id)
    @logger.info("snapshot #{snapshot_id} deleted")
    post_message("snapshot #{snapshot_id} deleted")
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
    @logger.debug "register snapshot #{snapshot_id} as #{name} using AKI '#{kernel_id}' ARI '#{ramdisk_id}' and arch '#{architecture}'"
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
    status = remote_handler().create_filesystem("ext3", device)
    if status == false
      raise Exception.new("failed to create ext3 filesystem on #{device} device on #{dns_name}")
    end
    post_message("filesystem system successfully created")
  end

  # Create a file-system on a given machine (assumes to be connected already).
  # Input Parameters:
  # * dns_name => IP used
  # * device => device to be used for file-system creation (e.g. /dev/sdj)
  # * type => filesystem type (ext2, ext3, ext4)
  # * label => add a label to the partition
  def create_labeled_fs(dns_name, device, type, label)
    post_message("going to create filesystem on #{dns_name} to #{device}...")
    @logger.debug "create filesystem of type '#{type}' (default is ext3) on '#{dns_name}' to '#{device}'"
    fs_type = "ext3"
    if !type.nil? && !type.empty?
      fs_type = type
    end
    @logger.debug "create '#{fs_type}' filesystem on device '#{device}'"
    status = remote_handler().create_filesystem(fs_type, device)
    if status == false
      raise Exception.new("failed to create #{type} filesystem on #{device} device on #{dns_name}")
    end
    post_message("#{fs_type} filesystem system successfully created on device #{device}")
    if !label.nil? && !label.empty?
      post_message("going to add label #{label} for device #{device}...")
      @logger.debug "add label '#{label}' to device '#{device}'"
      if remote_handler().set_device_label_ext(device, label, fs_type)
        post_message("label #{label} added to device #{device}")
      else
        raise Exception.new("failed to add label #{label} to device #{device}")
      end
    end
  end

  # Create a file-system on a given machine (assumes to be connected already).
  # Input Parameters:
  # * mount_point => directory to be mounted on the device
  # * device => device used for mounting
  def mount_fs_old(mount_point, device)
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

  def mount_fs(mount_point, device)
    post_message("going to mount #{device} on #{mount_point}...")
    @logger.debug "mount #{device} on #{mount_point}"
    if !remote_handler.file_exists?(mount_point)
      post_message("creating mount point #{mount_point}...")
      @logger.debug "creating mount point #{mount_point}"
      remote_handler().mkdir(mount_point)
    end
    #XXX: detect new kernel that have /dev/xvdX device node instaed of /dev/sdX
    if device =~ /\/dev\/sd[a-z]/
      if !remote_handler().file_exists?(device)
        post_message("'#{device}' device node not found, checking for new kernel support...")
        @logger.debug "'#{device}' device node not found, checking for new kernel support" 
        new_device = device.gsub('sd', 'xvd')
        if remote_handler().file_exists?(new_device)
          post_message("'#{new_device}' device node found")
          @logger.debug "'#{new_device}' device node found"
          device = new_device
        end
      end
    #elsif device =~/\/dev\/xvd[a-z]/
    end

    done = false
    timeout = 120
    while timeout > 0
      res = remote_handler().mount(device, mount_point)
      if remote_handler().drive_mounted?(mount_point)
        done = true
        timeout = 0
      end
      sleep(5)
      timeout -= 5
    end
    msg = ""
    if !done
      msg = "Failed to mount device '#{device}' to '#{mount_point}"
      @logger.error "#{msg}"
      raise Exception.new("device #{device} not mounted")
    else
      msg = "device #{device} successfully mounted" 
      @logger.info "#{msg}"
    end
    post_message("#{msg}")
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

  # Get root partition label
  def get_root_partition_label()
    post_message("Retrieving '/' root partition label if any...")
    @logger.debug "get root partition label"
    # get root device and then its label
    root_device = remote_handler().get_root_device()
    @logger.debug "Found '#{root_device}' as root device"
    label = remote_handler().get_device_label(root_device)
    @logger.debug "Found label '#{label}'"
    if label.nil? || label.empty?
      post_message("'/' root partition has no label specified")
    else
      post_message("'/' root partition label '#{label}' for root device node '#{root_device}'")
    end
    return label
  end

  # Get partition label
  def get_partition_label(part)
    post_message("Retrieving '#{part}' partition label if any...")
    @logger.debug "get #{part} partition label"
    # get part device and then its label
    part_device = remote_handler().get_partition_device(part)
    @logger.debug "Found '#{part_device}' as partition device"
    label = remote_handler().get_device_label(part_device)
    @logger.debug "Found label '#{label}'"
    if label.nil? || label.empty?
      post_message("'#{part}' partition has no label specified")
    else
      post_message("'#{part}' partition label '#{label}' for device node '#{part_device}'")
    end
    return label
  end

  # Get root filesytem type
  def get_root_partition_fs_type()
    post_message("Retrieving '/' root partition filesystem type...")
    @logger.debug "get root partition filesystel type"
    # get root device and then its fs type
    root_fs_type = remote_handler().get_root_fs_type()
    @logger.debug "Found '#{root_fs_type}' as root filesystem type"
    if root_fs_type.nil? || root_fs_type.empty?
      raise Exception.new("Failed to retrieve filesystem type for '/' root partition")
    else
      post_message("'/' root partition contains an #{root_fs_type} filesystem")
    end
    return root_fs_type
  end

  # Get root filesytem type and label
  def get_root_partition_fs_type_and_label()
    post_message("Retrieving '/' root partition filesystem type and label...")
    @logger.debug "get root partition filesystel type"
    # get root device and then its fs type
    root_fs_type = remote_handler().get_root_fs_type()
    @logger.debug "Found '#{root_fs_type}' as root filesystem type"
    if root_fs_type.nil? || root_fs_type.empty?
      raise Exception.new("Failed to retrieve filesystem type for '/' root partition")
    else
      post_message("'/' root partition contains an #{root_fs_type} filesystem")
    end
    root_device = remote_handler().get_root_device()
    @logger.debug "Found '#{root_device}' as root device"
    if root_device.nil? || root_device.empty?
      raise Exception.new("Failed to retrieve root device for '/' root partition")
    else
       post_message("'/' root partitition on root device '#{root_device}'")
    end
    root_label = remote_handler().get_device_label_ext(root_device, root_fs_type)
    @logger.debug "Found label '#{root_label}'"
    if root_label.nil? || root_label.empty?
      post_message("'/' root partition has no label specified")
    else
      post_message("'/' root partition label '#{root_label}' for root device node '#{root_device}'")
    end
    return root_fs_type, root_label
  end

  # Get partition filesytem type
  def get_partition_fs_type(part)
    post_message("Retrieving '#{part}' partition filesystem type...")
    @logger.debug "get #{part} partition filesystel type"
    # get partition device and then its fs type
    part_fs_type = remote_handler().get_partition_fs_type(part)
    @logger.debug "Found '#{part_fs_type}' as filesystem type"
    if part_fs_type.nil? || part_fs_type.empty?
      raise Exception.new("Failed to retrieve filesystem type for '#{part}' partition")
    else
      post_message("'#{part}' partition contains an #{part_fs_type} filesystem")
    end
    return part_fs_type
  end

  # Get partition filesytem type and label
  def get_partition_fs_type_and_label(part)
    post_message("Retrieving '#{part}' partition filesystem type...")
    @logger.debug "get #{part} partition filesystel type"
    # get partition device and then its fs type
    part_fs_type = remote_handler().get_partition_fs_type(part)
    @logger.debug "Found '#{part_fs_type}' as filesystem type"
    if part_fs_type.nil? || part_fs_type.empty?
      raise Exception.new("Failed to retrieve filesystem type for '#{part}' partition")
    else
      post_message("'#{part}' partition contains an #{part_fs_type} filesystem")
    end
    part_device = remote_handler().get_partition_device(part)
    @logger.debug "Found '#{part_device}' as partition device"
    if part_device.nil? || part_device.empty?
      raise Exception.new("Failed to retrieve device for '#{part}' partition")
    else
       post_message("'#{part}' partitition on device '#{part_device}'")
    end
    part_label = remote_handler().get_device_label_ext(part_device, part_fs_type)
    @logger.debug "Found label '#{part_label}'"
    if part_label.nil? || part_label.empty?
      post_message("'#{part}' partition has no label specified")
    else
      post_message("'#{part}' partition label '#{part_label}' for device node '#{part_device}'")
    end
    return part_fs_type, part_label
  end

  # Copy all files of a running linux distribution via rsync to a mounted directory
  # Input Parameters:
  # * destination_path => where to copy to
  def copy_distribution(destination_path)
    post_message("going to start copying files to #{destination_path}. This may take quite a time...")
    @logger.debug "start copying to #{destination_path}"
    start = Time.new.to_i
    if remote_handler().tools_installed?("rsync")
      @logger.debug "use rsync command line"
      status = remote_handler().local_rsync("/", "#{destination_path}", "#{destination_path}")
      status = remote_handler().local_rsync("/dev/", "#{destination_path}/dev/")
      if status == false
        raise Exception.new("failed to copy distribution remotely using rsync")
      end
    else
      @logger.debug "use cp command line"
      status = remote_handler().local_rcopy("/", "#{destination_path}", "/proc /sys /dev /mnt")
      if status == false
        raise Exception.new("failed to copy distribution remotely using cp")
      end
      status = remote_handler().mkdir("#{destination_path}/proc")
      status = remote_handler().mkdir("#{destination_path}/sys")
      status = remote_handler().mkdir("#{destination_path}/mnt")
      status = remote_handler().mkdir("#{destination_path}/dev")
    end
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
    stderr = remote_handler().zip(source_dir, zip_file_dest+"/"+zip_file_name)
    if stderr.size > 0
      @logger.info("zip operation generated error and might not be complete. output: #{stderr.join("\n")}")
      post_message("zip operation generated error and might not be complete. output: #{stderr.join("\n")}")
    end
    post_message("EBS volume successfully zipped")
  end

  def remote_copy_old(user_name, keyname, source_dir, dest_machine, dest_dir)
    post_message("going to remote copy all files from volume. This may take some time...")
    key_path_candidates = ["/#{user_name}/.ssh/", "/home/#{user_name}/.ssh/"]
    key_path_candidates.each() {|key_path|
      key_file = "#{key_path}#{keyname}.pem"
      if remote_handler().file_exists?(key_path)
        if remote_handler().tools_installed?("rsync")
          @logger.debug "use rsync command on #{key_file}"
          remote_handler().remote_rsync(key_file, source_dir, dest_machine, dest_dir)
        else
          @logger.debug "use scp command #{key_file}"
          remote_handler().scp(key_file, source_dir, dest_machine, dest_dir)
        end
        break
      end
    }
    post_message("remote copy operation done")
  end

  def disable_ssh_tty(host)
    post_message("going to disable SSH tty on #{host}...")
    @logger.debug "disable SSH tty on "
    remote_handler().disable_sudoers_requiretty()
    post_message("SSH tty disabled")
  end

  def enable_ssh_tty(host)
    post_message("going to enable SSH tty on #{host}...")
    @logger.debug "enable SSH tty on"
    remote_handler().enable_sudoers_requiretty()
    post_message("SSH tty enabled")
  end

  def remote_copy(user_name, keyname, source_dir, dest_machine, dest_user, dest_dir)
    post_message("going to remote copy all files from volume. This may take some time...")
    key_path_candidates = ["/#{user_name}/.ssh/", "/home/#{user_name}/.ssh/"]
    key_path_candidates.each() {|key_path|
      key_file = "#{key_path}#{keyname}.pem"
      if remote_handler().file_exists?(key_path)
        if remote_handler().tools_installed?("rsync")
          @logger.debug "use rsync command on #{key_file}"
          remote_handler().remote_rsync(key_file, source_dir, dest_machine, dest_user, dest_dir)
        else
          @logger.debug "use scp command #{key_file}"
          remote_handler().scp(key_file, source_dir, dest_machine, dest_user, dest_dir)
        end
        break
      end
    }
    post_message("remote copy operation done")
  end

  def upload_file(ip, user, key_data, file, target_file)
    post_message("going to upload #{file} to #{user}@#{ip}:#{target_file}")
    remote_handler().upload(ip, user, key_data, file, target_file)
  end

  # From a list of existing files, return the first that exists
  def determine_file(ip, user_name, ssh_keydata, file_candidates)
    connect(ip, user_name, nil, ssh_keydata)
    begin
      file_candidates.each() {|file_path|
        if remote_handler().file_exists?(file_path)
          return file_path
        end
      }
      return nil
    rescue
      raise
    ensure
      disconnect()
    end
  end

  # Mapping AmazonKernel Image IDs
  # From documentation: http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?UserProvidedkernels.html
  # * US-East-1
  #    aki-4c7d9525 ec2-public-images/pv-grub-hd00-V1.01-i386.gz.manifest.xml
  #    aki-4e7d9527 ec2-public-images/pv-grub-hd00-V1.01-x86_64.gz.manifest.xml
  #    aki-407d9529 ec2-public-images/pv-grub-hd0-V1.01-i386.gz.manifest.xml
  #    aki-427d952b ec2-public-images/pv-grub-hd0-V1.01-x86_64.gz.manifest.xml
  #    aki-525ea73b ec2-public-images/pv-grub-hd00_1.02-i386.gz.manifest.xml
  #    aki-8e5ea7e7 ec2-public-images/pv-grub-hd00_1.02-x86_64.gz.manifest.xml
  #    aki-805ea7e9 ec2-public-images/pv-grub-hd0_1.02-i386.gz.manifest.xml
  #    aki-825ea7eb ec2-public-images/pv-grub-hd0_1.02-x86_64.gz.manifest.xml
  # * US-West-1
  #    aki-9da0f1d8 ec2-public-images-us-west-1/pv-grub-hd00-V1.01-i386.gz.manifest.xml
  #    aki-9fa0f1da ec2-public-images-us-west-1/pv-grub-hd00-V1.01-x86_64.gz.manifest.xml
  #    aki-99a0f1dc ec2-public-images-us-west-1/pv-grub-hd0-V1.01-i386.gz.manifest.xml
  #    aki-9ba0f1de ec2-public-images-us-west-1/pv-grub-hd0-V1.01-x86_64.gz.manifest.xml
  #    aki-87396bc2 ec2-public-images-us-west-1/pv-grub-hd00_1.02-i386.gz.manifest.xml
  #    aki-81396bc4 ec2-public-images-us-west-1/pv-grub-hd00_1.02-x86_64.gz.manifest.xml
  #    aki-83396bc6 ec2-public-images-us-west-1/pv-grub-hd0_1.02-i386.gz.manifest.xml
  #    aki-8d396bc8 ec2-public-images-us-west-1/pv-grub-hd0_1.02-x86_64.gz.manifest.xml
  # * EU-West-1
  #    aki-47eec433 ec2-public-images-eu/pv-grub-hd00-V1.01-i386.gz.manifest.xml
  #    aki-41eec435 ec2-public-images-eu/pv-grub-hd00-V1.01-x86_64.gz.manifest.xml
  #    aki-4deec439 ec2-public-images-eu/pv-grub-hd0-V1.01-i386.gz.manifest.xml
  #    aki-4feec43b ec2-public-images-eu/pv-grub-hd0-V1.01-x86_64.gz.manifest.xml
  #    aki-8a6657fe ec2-public-images-eu/pv-grub-hd00_1.02-i386.gz.manifest.xml
  #    aki-60695814 ec2-public-images-eu/pv-grub-hd00_1.02-x86_64.gz.manifest.xml
  #    aki-64695810 ec2-public-images-eu/pv-grub-hd0_1.02-i386.gz.manifest.xml
  #    aki-62695816 ec2-public-images-eu/pv-grub-hd0_1.02-x86_64.gz.manifest.xml
  # * AP-SouthEast-1
  #    aki-6fd5aa3d ec2-public-images-ap-southeast-1/pv-grub-hd00-V1.01-i386.gz.manifest.xml
  #    aki-6dd5aa3f ec2-public-images-ap-southeast-1/pv-grub-hd00-V1.01-x86_64.gz.manifest.xml
  #    aki-13d5aa41 ec2-public-images-ap-southeast-1/pv-grub-hd0-V1.01-i386.gz.manifest.xml
  #    aki-11d5aa43 ec2-public-images-ap-southeast-1/pv-grub-hd0-V1.01-x86_64.gz.manifest.xml
  #    aki-a0225af2 ec2-public-images-ap-southeast-1/pv-grub-hd00_1.02-i386.gz.manifest.xml
  #    aki-a6225af4 ec2-public-images-ap-southeast-1/pv-grub-hd00_1.02-x86_64.gz.manifest.xml
  #    aki-a4225af6 ec2-public-images-ap-southeast-1/pv-grub-hd0_1.02-i386.gz.manifest.xml
  #    aki-aa225af8 ec2-public-images-ap-southeast-1/pv-grub-hd0_1.02-x86_64.gz.manifest.xml
  # * AP-NorthEast-1
  #    aki-d209a2d3 ec2-public-images-ap-northeast-1/pv-grub-hd0-V1.01-i386.gz.manifest.xml
  #    aki-d409a2d5 ec2-public-images-ap-northeast-1/pv-grub-hd0-V1.01-x86_64.gz.manifest.xml
  #    aki-d609a2d7 ec2-public-images-ap-northeast-1/pv-grub-hd00-V1.01-i386.gz.manifest.xml
  #    aki-d809a2d9 ec2-public-images-ap-northeast-1/pv-grub-hd00-V1.01-x86_64.gz.manifest.xml
  #    aki-e85df7e9 ec2-public-images-ap-northeast-1/pv-grub-hd00_1.02-i386.gz.manifest.xml
  #    aki-ea5df7eb ec2-public-images-ap-northeast-1/pv-grub-hd00_1.02-x86_64.gz.manifest.xml
  #    aki-ec5df7ed ec2-public-images-ap-northeast-1/pv-grub-hd0_1.02-i386.gz.manifest.xml
  #    aki-ee5df7ef ec2-public-images-ap-northeast-1/pv-grub-hd0_1.02-x86_64.gz.manifest.xml
  def get_aws_kernel_image_aki(source_region, source_aki, target_region)
    map = { 'us-east-1' => {'aki-4c7d9525' => 'pv-grub-hd00-V1.01-i386',
                            'aki-4e7d9527' => 'pv-grub-hd00-V1.01-x86_64',
                            'aki-407d9529' => 'pv-grub-hd0-V1.01-i386',
                            'aki-427d952b' => 'pv-grub-hd0-V1.01-x86_64',
                            'aki-525ea73b' => 'pv-grub-hd00_1.02-i386',
                            'aki-8e5ea7e7' => 'pv-grub-hd00_1.02-x86_64',
                            'aki-805ea7e9' => 'pv-grub-hd0_1.02-i386',
                            'aki-825ea7eb' => 'pv-grub-hd0_1.02-x86_64'
                           }, 
            'us-west-1' => {'aki-9da0f1d8' => 'pv-grub-hd00-V1.01-i386',
                            'aki-9fa0f1da' => 'pv-grub-hd00-V1.01-x86_64',
                            'aki-99a0f1dc' => 'pv-grub-hd0-V1.01-i386',
                            'aki-9ba0f1de' => 'pv-grub-hd0-V1.01-x86_64',
                            'aki-87396bc2' => 'pv-grub-hd00_1.02-i386',
                            'aki-81396bc4' => 'pv-grub-hd00_1.02-x86_64',
                            'aki-83396bc6' => 'pv-grub-hd0_1.02-i386',
                            'aki-8d396bc8' => 'pv-grub-hd0_1.02-x86_64'
                           },
            'eu-west-1' => {'aki-47eec433' => 'pv-grub-hd00-V1.01-i386',
                            'aki-41eec435' => 'pv-grub-hd00-V1.01-x86_64',
                            'aki-4deec439' => 'pv-grub-hd0-V1.01-i386',
                            'aki-4feec43b' => 'pv-grub-hd0-V1.01-x86_64',
                            'aki-8a6657fe' => 'pv-grub-hd00_1.02-i386',
                            'aki-60695814' => 'pv-grub-hd00_1.02-x86_64',
                            'aki-64695810' => 'pv-grub-hd0_1.02-i386',
                            'aki-62695816' => 'pv-grub-hd0_1.02-x86_64'
                           },
            'ap-southeast-1' => {'aki-6fd5aa3d' => 'pv-grub-hd00-V1.01-i386',
                                 'aki-6dd5aa3f' => 'pv-grub-hd00-V1.01-x86_64',
                                 'aki-13d5aa41' => 'pv-grub-hd0-V1.01-i386',
                                 'aki-11d5aa43' => 'pv-grub-hd0-V1.01-x86_64',
                                 'aki-a0225af2' => 'pv-grub-hd00_1.02-i386',
                                 'aki-a6225af4' => 'pv-grub-hd00_1.02-x86_64',
                                 'aki-a4225af6' => 'pv-grub-hd0_1.02-i386',
                                 'aki-aa225af8' => 'pv-grub-hd0_1.02-x86_64'
                           },
            'ap-northeast-1' => {'aki-d209a2d3' => 'pv-grub-hd00-V1.01-i386',
                                 'aki-d409a2d5' => 'pv-grub-hd00-V1.01-x86_64',
                                 'aki-d609a2d7' => 'pv-grub-hd0-V1.01-i386',
                                 'aki-d809a2d9' => 'pv-grub-hd0-V1.01-x86_64',
                                 'aki-e85df7e9' => 'pv-grub-hd00_1.02-i386',
                                 'aki-ea5df7eb' => 'pv-grub-hd00_1.02-x86_64',
                                 'aki-ec5df7ed' => 'pv-grub-hd0_1.02-i386',
                                 'aki-ee5df7ef' => 'pv-grub-hd0_1.02-x86_64'
                           }
          }
    target_aki = ''
    post_message("mapping AKI '#{source_aki}' from #{source_region} region to #{target_region} region...")

    if map[source_region] == nil
      Exception.new("source region not supported")
    elsif map[target_region] == nil
      Exception.new("target region not supported")
    else
      if map[source_region][source_aki] == nil
        Exception.new("aki not found in source region")
      else
        pv_grub_info = map[source_region][source_aki]
        map[target_region].each() {|key, value|
          if pv_grub_info.eql?(value)
            @logger.debug "found AKI: #{key} for #{value}"
            target_aki = key
            break
          end
        }
      end
    end
    post_message("AKI mapped to #{target_aki}")
    return target_aki
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
