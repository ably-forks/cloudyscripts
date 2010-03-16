module StateTransitionHelper

  def connect
    @context[:script].post_message("connecting to #{@context[:dns_name]}...")
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
    @context[:script].post_message("connected to #{@context[:dns_name]}. OS installed is #{@context[:result][:os]}")
    @logger.info "connected to #{@context[:dns_name]}"
  end

  def launch_instance
    @context[:script].post_message("starting up instance to execute the script (AMI = #{@context[:ami_id]}) ...")
    @logger.debug "start up AMI #{@context[:ami_id]}"
    res = @context[:ec2_api_handler].run_instances(:image_id => @context[:ami_id],
      :security_group => @context[:security_group_name], :key_name => @context[:key_name])
    instance_id = res['instancesSet']['item'][0]['instanceId']
    @context[:instance_id] = instance_id
    @logger.info "started instance #{instance_id}"
    @context[:script].post_message("started instance #{instance_id}. wait until it is ready...")
    #availability_zone , key_name/group_name
    started = false
    while started == false
      sleep(5)
      res = @context[:ec2_api_handler].describe_instances(:instance_id => @context[:instance_id])
      state = res['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']
      @logger.info "instance is in state #{state['name']} (#{state['code']})"
      if state['code'].to_i == 16
        started = true
        @context[:script].post_message("instance is up and running")
        @context[:dns_name] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['dnsName']
        @context[:availability_zone] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['placement']['availabilityZone']
        @context[:kernel_id] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['kernelId']
        @context[:ramdisk_id] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['ramdiskId']
        @context[:architecture] = res['reservationSet']['item'][0]['instancesSet']['item'][0]['architecture']
      elsif state['code'].to_i != 0
        @context[:script].post_message("instance in state #{state['name']}")
        raise Exception.new('instance failed to start up')
      else
        @context[:script].post_message("instance still starting up...")
      end
    end
  end

  def shut_down_instance()
    @context[:script].post_message("going to shut down the temporary instance #{@context[:instance_id]}...")
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
    @context[:script].post_message("instance #{@context[:instance_id]} is terminated")
  end

  def create_volume()
    @context[:script].post_message("going to create a new EBS volume...")
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
    @context[:script].post_message("EBS volume #{@context[:volume_id]} is ready")
  end

  def create_volume_from_snapshot
    @context[:script].post_message("going to create a new EBS volume from the specified snapshot...")
    @logger.debug "create volume in zone #{@context[:availability_zone]}"
    res = @context[:ec2_api_handler].create_volume(:snapshot_id => @context[:snapshot_id], :availability_zone => @context[:availability_zone], :size => "10")
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
    @context[:script].post_message("EBS volume #{@context[:volume_id]} is ready")
  end

  def attach_volume
    @context[:script].post_message("going to attach volume #{@context[:volume_id]} to instance #{@context[:instance_id]} on device #{@context[:temp_device_name]}...")
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
    @context[:script].post_message("volume successfully attached")
  end

  def detach_volume()
    @context[:script].post_message("going to detach volume #{@context[:volume_id]}...")
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
    @context[:script].post_message("volume #{@context[:volume_id]} detached.")
  end

  def delete_volume
    @context[:script].post_message("going to delete volume #{@context[:volume_id]} (no longer needed)...")
    @logger.debug "delete volume #{@context[:volume_id]}"
    @context[:ec2_api_handler].delete_volume(:volume_id => @context[:volume_id])
    @context[:script].post_message("volume #{@context[:volume_id]} deleted")
  end

  def create_snapshot()
    @context[:script].post_message("going to create a snapshot...")
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
    @context[:script].post_message("snapshot is done with ID=#{@context[:snapshot_id]}")
  end

  def register_snapshot()
    @context[:script].post_message("going to register snapshot #{@context[:snapshot_id]}...")
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
    @context[:script].post_message("snapshot #{@context[:snapshot_id]} successfully registered as AMI #{@context[:result][:image_id]} ")
  end

  def create_fs()
    @context[:script].post_message("going to create filesystem on #{@context[:dns_name]} to #{@context[:temp_device_name]}...")
    @logger.debug "create filesystem on #{@context[:dns_name]} to #{@context[:temp_device_name]}"
    connect()
    @context[:remote_command_handler].create_filesystem("ext3", @context[:temp_device_name])
    @context[:script].post_message("filesystem system successfully created")
  end

  def mount_fs()
    @context[:path] = "/mnt/tmp_#{@context[:volume_id]}"
    @context[:script].post_message("going to mount #{@context[:temp_device_name]} on #{@context[:path]}...")
    @logger.debug "mount #{@context[:temp_device_name]} on #{@context[:path]}"
    @context[:remote_command_handler].mkdir(@context[:path])
    @context[:remote_command_handler].mount(@context[:temp_device_name], @context[:path])
    sleep(2) #give mount some time
    if !@context[:remote_command_handler].drive_mounted?(@context[:path])
      raise Exception.new("drive #{@context[:path]} not mounted")
    end
    @context[:script].post_message("mount successful")
  end

  def unmount_fs()
    @context[:script].post_message("Going to unmount ...")
    @logger.debug "unmount #{@context[:path]}"
    @context[:remote_command_handler].umount(@context[:path])
    sleep(2) #give umount some time
    if @context[:remote_command_handler].drive_mounted?(@context[:path])
      raise Exception.new("drive #{@context[:path]} not unmounted")
    end
    @context[:script].post_message("device unmounted")
  end

  def copy()
    @context[:script].post_message("going to start copying files to #{@context[:path]}. This may take quite a time...")
    @logger.debug "start copying to #{@context[:path]}"
    start = Time.new.to_i
    @context[:remote_command_handler].rsync("/", "#{@context[:path]}", "/mnt/")
    @context[:remote_command_handler].rsync("/dev/", "#{@context[:path]}/dev/")
    endtime = Time.new.to_i
    @logger.info "copy took #{(endtime-start)}s"
    @context[:script].post_message("copying is done (took #{endtime-start})s")
  end

  def zip_volume
    @context[:script].post_message("going to zip the EBS volume")
    @context[:remote_command_handler].zip(@context[:path], @context[:zip_file_dest]+@context[:zip_file_name])
    @context[:script].post_message("EBS volume successfully zipped")
  end

end
