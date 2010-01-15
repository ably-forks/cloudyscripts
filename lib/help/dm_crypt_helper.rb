require 'help/remote_command_handler'

# This class implements helper methods for Dm Encryption
# (see #Scripts::EC2::DmEncrypt)

class DmCryptHelper < RemoteCommandHandler
  
  # Encrypts the device and mounting it using dm-crypt tools. Uses LVM to
  # work with virtual devices.
  # Params
  # * name: name of the virtual volume
  # * password: paraphrase to be used for encryption
  # * device: device to be encrypted
  # * path: path to which the encrypted device is mounted
  def encrypt_storage_lvm(name, password, device, path)
    # first: check if a file in /dev/mapper exists
    if file_exists?("/dev/mapper/dm-#{name}")
      mapper_exists = true
    else
      mapper_exists = false
    end
    @logger.info "mapper exists = #{mapper_exists}"
    exec_string = "cryptsetup create dm-#{name} #{device}"
    if !mapper_exists
      #mapper does not exist, create it
      channel = @ssh_session.open_channel do |ch|
        ch.send_data("#{password}\n")
        @logger.debug "execute #{exec_string}"
        ch.exec exec_string do |ch, success|
          @logger.debug "success = #{success}"
          if !success
            err = "Failed during creation of encrypted partition"
            #puts "#{err}: #{data}"
            raise Exception.new(err)
          end
        end
      end
      channel.wait
    end
    # now mapper is created
    # second: check if pvscan sucessful
    pv_exists = false
    @ssh_session.exec! "/sbin/pvscan" do |ch, stream, data|
      if stream == :stdout
        if data.include?("vg-#{name}")
          pv_exists = true
        else
          pv_exists = false
        end
      end
    end
    if !pv_exists
      exec_string = "pvcreate /dev/mapper/dm-#{name}"
      @logger.info "pv does not exist - execute: #{exec_string}"
      #private volume does not exist, create it
      channel = @ssh_session.open_channel do |ch|
        ch.send_data("y\n")
        ch.exec exec_string do |ch, success|
          @logger.debug "success = #{success}"
          if !success
            err = "Failed during creation of physical volume"
            #puts "#{err}: #{data}"
            raise Exception.new(err)
          end
        end
      end
      channel.wait
    end
    # third: check if vgscan successful
    vg_exists = false
    @ssh_session.exec! "/sbin/vgscan" do |ch, stream, data|
      if stream == :stdout
        if data.include?("vg-#{name}")
          vg_exists = true
        else
          vg_exists = false
        end
      end
    end
    if !vg_exists
      exec_string = "vgcreate vg-#{name} /dev/mapper/dm-#{name}"
      @logger.info "vg_exists == false; execute #{exec_string}"
      @ssh_session.exec! exec_string do |ch, stream, data|
        if stream == :stderr && data != nil
          err = "Failed during creation of volume group"
          @logger.warn "#{err}: #{data}"
          raise Exception.new(err)
        end
      end
      #exec_string = "lvcreate -n lv-#{name} -L#{size_in_mb.to_s}M vg-#{name}"
      exec_string = "lvcreate -n lv-#{name} -l100%FREE vg-#{name}"
      @logger.info "execute #{exec_string}"
      @ssh_session.exec! exec_string do |ch, stream, data|
        if stream == :stderr && data != nil
          err = "Failed during creation of logical volume"
          @logger.debug "#{err}: #{data}"
          raise Exception.new(err)
        end
      end
      exec_string = "mkfs -t ext3 /dev/vg-#{name}/lv-#{name}" #TODO: use method in remote_command_handler
      @logger.info "execute #{exec_string}"
      @ssh_session.exec! exec_string #do |ch, stream, data|
        #if stream == :stderr && data != nil
        #err = "Failed during creation of file-system"
        #puts "#{err}: #{data}"
        #raise Exception.new(err)
        #end
      #end
      if !file_exists?("/dev/vg-#{name}/lv-#{name}")
        err = "Missing file: /dev/vg-#{name}/lv-#{name}"
        raise Exception.new(err)
      end
    else
      exec_string = "/sbin/vgchange -a y vg-#{name}"
      @logger.info "vg_exists == true; execute #{exec_string}"
      @ssh_session.exec! exec_string do |ch, stream, data| #TODO: the right size instead L2G!
        if stream == :stderr && data != nil
          err = "Failed during re-activation of volume group"
          @logger.info "#{err}: #{data}"
          raise Exception.new(err)
        end
      end
    end
  end

  # Undo encryption for the volume specified by name and path
  def undo_encryption_lvm(name, path)
    exec_string = "umount #{path}"
    @logger.debug "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      @logger.debug "returns #{data}"
    end
    exec_string = "lvremove --verbose vg-#{name} -f" #[with confirmation?]
    @logger.debug "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      @logger.debug "returns #{data}"
    end
    exec_string = "vgremove vg-#{name}"
    @logger.debug "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      @logger.debug "returns #{data}"
    end
    exec_string = "pvremove /dev/mapper/dm-#{name}"
    @logger.debug "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      @logger.debug "returns #{data}"
    end
    exec_string = "cryptsetup remove dm-#{name}"
    @logger.debug "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      @logger.debug "returns #{data}"
    end
  end

  # Encrypts the device and mounting it using dm-crypt tools.
  # Params
  # * name: name of the virtual volume
  # * password: paraphrase to be used for encryption
  # * device: device to be encrypted
  # * path: path to which the encrypted device is mounted
  def encrypt_storage(name, password, device, path)
    if !RemoteCommandHandler.remote_execute(@ssh_session, @logger, "cryptsetup isLuks #{device}")
      raise Exception.new("device #{device} is already used differently")
    end
    if file_exists?(device)
      if !file_exists?("/dev/mapper/#{name}")
        @logger.debug("mapper device #{name} not yet existing")
        #device not configured, go ahead
        RemoteCommandHandler.remote_execute(@ssh_session, @logger, "cryptsetup luksFormat  -q #{device}", password)
        @logger.debug("device #{device} formatted as #{name}")
        RemoteCommandHandler.remote_execute(@ssh_session, @logger, "cryptsetup luksOpen #{device} #{name}",password)
        @logger.debug("device #{device} / #{name} opened")
        self.create_filesystem("ext3", "/dev/mapper/#{name}")
        @logger.debug("filesystem created on /dev/mapper/#{name}")
        self.mkdir(path)
        self.mount("/dev/mapper/#{name}", path)
        #TODO: make a final check that everything worked? ?
      else
        #device already exists, just re-activate it
        @logger.debug("mapper device #{name} is existing")
        RemoteCommandHandler.remote_execute(@ssh_session, @logger, "cryptsetup luksOpen #{device} #{name}")
        @logger.debug("device #{device} /dev/mapper/#{name} opened")
        self.mkdir(path) unless file_exists?(path)
        self.mount("/dev/mapper/#{name}", path) unless drive_mounted_as?("/dev/mapper/#{name}", path)
      end
    else
      #device does not even exist
      raise Exception.new("device #{device} does not exist")
    end

  end

  # Check if the storage is encrypted (not yet implemented).
  def test_storage_encryption(password, mount_point, path)
  end

  def undo_encryption(name, path)
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, "umount #{path}", nil, true)
    @logger.debug("drive #{path} unmounted")
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, "cryptsetup luksClose /dev/mapper/#{name}", nil, true)
    @logger.debug("closed /dev/mapper/#{name} unmounted")
  end

end
