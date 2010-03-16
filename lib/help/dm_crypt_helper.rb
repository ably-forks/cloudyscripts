require 'help/remote_command_handler'

# This class implements helper methods for Dm Encryption
# (see #Scripts::EC2::DmEncrypt)

class DmCryptHelper < RemoteCommandHandler
  # Encrypts the device and mounting it using dm-crypt tools.
  # Params
  # * name: name of the virtual volume
  # * password: paraphrase to be used for encryption
  # * device: device to be encrypted
  # * path: path to which the encrypted device is mounted
  def encrypt_storage(name, password, device, path)
    if file_exists?(device)
      if !file_exists?("/dev/mapper/#{name}")
        @logger.debug("mapper device #{name} not yet existing")
        #device not configured, go ahead
        remote_execute("cryptsetup luksFormat  -q #{device}", password)
        @logger.debug("device #{device} formatted as #{name}")
        remote_execute("cryptsetup luksOpen #{device} #{name}",password)
        @logger.debug("device #{device} / #{name} opened")
        self.create_filesystem("ext3", "/dev/mapper/#{name}")
        @logger.debug("filesystem created on /dev/mapper/#{name}")
        self.mkdir(path)
        self.mount("/dev/mapper/#{name}", path)
        #TODO: make a final check that everything worked? ?
      else
        #device already exists, just re-activate it
        @logger.debug("mapper device #{name} is existing")
        remote_execute("cryptsetup luksOpen #{device} #{name}")
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
    remote_execute("umount #{path}", nil, true)
    @logger.debug("drive #{path} unmounted")
    remote_execute("cryptsetup luksClose /dev/mapper/#{name}", nil, true)
    @logger.debug("closed /dev/mapper/#{name} unmounted")
  end

end
