require 'rubygems'
require 'net/ssh'
require 'help/dm_crypt_helper'

# Provides methods to be executed via ssh to remote instances.
class RemoteCommandHandler
  attr_accessor :logger, :ssh_session
  def initialize
    @crypto = DmCryptHelper.new #TODO: instantiate helpers for different tools
    @logger = Logger.new(STDOUT)
  end

  # Connect to the machine as root using a keyfile.
  # Params:
  # * ip: ip address of the machine to connect to
  # * keyfile: path of the keyfile to be used for authentication
  def connect_with_keyfile(ip, keyfile)
    @ssh_session = Net::SSH.start(ip, 'root', :keys => [keyfile])
    @crypto.set_ssh(@ssh_session)
  end

  # Connect to the machine as root using keydata from a keyfile.
  # Params:
  # * ip: ip address of the machine to connect to
  # * user: user name
  # * key_data: key_data to be used for authentication
  def connect(ip, user, key_data)
    @ssh_session = Net::SSH.start(ip, user, :key_data => [key_data])
    @crypto.set_ssh(@ssh_session)
  end

  # Disconnect the current handler
  def disconnect
    @ssh_session.close
  end

  # Check if the path/file specified exists
  def self.file_exists?(ssh_session, path)
    RemoteCommandHandler.remote_execute(ssh_session, nil, "ls #{path}")
  end
  
  # Installs the software package specified.
  def install(software_package)
    e = "yum -yq install #{software_package}; apt-get -yq install #{software_package}"
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, e)
  end

  # Checks if the software package specified is installed.
  def tools_installed?(software_package)
    e = "which #{software_package}"
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, e)
  end

  # Encrypt the storage (using the crypto-helper used, e.g. #Help::DmCryptHelper)
  def encrypt_storage(name, password, device, path)
    @crypto.encrypt_storage(name, password, device, path)
  end

  # Check if the storage is encrypted (using the crypto-helper used, e.g. #Help::DmCryptHelper)
  def storage_encrypted?(password, device, path)
    drive_mounted?(path) #TODO: must at least also check the name
  end

  def create_filesystem(fs_type, volume)
    e = "mkfs -t #{fs_type} #{volume}"
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, e, "y")
  end

  def mkdir(path)
    e = "mkdir #{path}"
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, e, nil, true)
  end

  def mount(device, path)
    e = "mount #{device} #{path}"
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, e, nil, true)
  end

  # Checks if the drive on path is mounted
  def drive_mounted?(path)
    #check if drive mounted
    drive_found = false
    @ssh_session.exec! "mount" do |ch, stream, data|
      if stream == :stdout
        @logger.debug "mount command produces the following data: #{data}\n---------------"
        if data.include?("on #{path} type")
          drive_found = true
        end
      end
    end
    if drive_found
      return RemoteCommandHandler.file_exists?(@ssh_session, path)
    else
      @logger.debug "not mounted (since #{path} non-existing)"
      false
    end
  end

  # Checks if the drive on path is mounted with the specific device
  def drive_mounted_as?(device, path)
    #check if drive mounted
    drive_mounted = false
    @ssh_session.exec! "mount" do |ch, stream, data|
      if stream == :stdout
        if data.include?("#{device} on #{path} type")
          drive_mounted = true
        end
      end
    end
    drive_mounted
  end

  # Activates the encrypted volume, i.e. mounts it if not yet done.
  def activate_encrypted_volume(name, path)
    drive_mounted = drive_mounted?(path)
    @logger.debug "drive #{path} mounted? #{drive_mounted}"
    if !drive_mounted
      mkdir(path)
      mount("/dev/vg-#{name}/lv-#{name}", "#{path}")
    end
  end

  # Unconfigure the storage (using the crypto-helper used, e.g. #Help::DmCryptHelper)
  def undo_encryption(name, path)
    @crypto.undo_encryption(name, path)
  end

  # Unmount the specified path.
  def umount(path)
    exec_string = "umount #{path}"
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, exec_string)
    !drive_mounted?(path)
  end
  
  # Copy directory using options -avHx
  def rsync(source_path, dest_path)
    e = "rsync -avHx #{source_path} #{dest_path}"
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, e, nil, true)
  end

  private

  # Executes the specified #exec_string on a remote session specified as #ssh_session
  # and logs the command-output into the specified #logger. When #push_data is
  # specified, the data will be used as input for the command and thus allows
  # to respond in advance to commands that ask the user something.
  # The method will return true if nothing was written into stderr, otherwise false.
  # When #raise_exception is set, an exception will be raised instead of
  # returning false.
  def self.remote_execute(ssh_session, logger, exec_string, push_data = nil, raise_exception = false)
    result = true
    exec_string = "echo #{push_data} >tmp.txt; #{exec_string} <tmp.txt; rm -f tmp.txt" unless push_data == nil
    output = ""
    ssh_session.exec!(exec_string) do |ch, stream, data|
      output += data unless data == nil
      if stream == :stderr && data != nil
        result = false
      end
    end
    logger.info output unless logger == nil
    raise Exception.new("RemoteCommandHandler: #{exec_string} lead to stderr message: #{output}") unless result == true || raise_exception == false
    result
  end

end
