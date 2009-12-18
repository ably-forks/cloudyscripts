require 'rubygems'
require 'net/ssh'

# Provides methods to be executed via ssh to remote instances.
class RemoteCommandHandler
  def initialize
    @crypto = DmCryptHelper.new #TODO: instantiate helpers for different tools
  end

  # Check if the path/file specified exists
  def self.file_exists?(ssh_session, path)
    result = true
    ssh_session.exec!("ls #{path}") do |ch, stream, data|
      if stream == :stderr
        result = false
      end
    end
    result
  end

  # Connect to the machine as root using a keyfile.
  # Params:
  # * ip: ip address of the machine to connect to
  # * keyfile: path of the keyfile to be used for authentication
  def connect(ip, keyfile)
    @ssh_session = Net::SSH.start(ip, 'root', :keys => [keyfile])
    @crypto.set_ssh(@ssh_session)
  end

  # Disconnect the current handler
  def disconnect
    @ssh_session.close
  end

  # Installs the software package specified.
  def install(software_package)
    @crypto.install()
  end

  # Checks if the software package specified is installed.
  def tools_installed?(software_package)
    @crypto.tools_installed?
  end

  # Encrypt the storage (using the crypto-helper used, e.g. #Help::DmCryptHelper)
  def encrypt_storage(name, password, device, path)
    @crypto.encrypt_storage(name, password, device, path)
  end

  # Check if the storage is encrypted (using the crypto-helper used, e.g. #Help::DmCryptHelper)
  def storage_encrypted?(password, device, path)
    drive_mounted?(path) #TODO: must at least also check the name
  end

  # Checks if the drive on path is mounted
  def drive_mounted?(path)
    #check if drive mounted
    drive_found = false
    @ssh_session.exec! "mount" do |ch, stream, data|
      if stream == :stdout
        puts "mount command produces the following data: #{data}\n---------------"
        if data.include?("on #{path} type")
          drive_found = true
        else
          puts "not mounted: #{data}"
        end
      end
    end
    if drive_found
      return SshApi.file_exists?(@ssh_session, path)
    else
      puts "not mounted (since #{path} non-existing)"
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
        else
          puts "not mounted: #{data}"
        end
      end
    end
    drive_mounted
  end

  # Activates the encrypted volume, i.e. mounts it if not yet done.
  def activate_encrypted_volume(name, path)
    drive_mounted = drive_mounted?(path)
    puts "drive #{path} mounted? #{drive_mounted}"
    if !drive_mounted
      @ssh_session.exec! "mkdir #{path}"
      exec_string = "mount /dev/vg-#{name}/lv-#{name} #{path}"
      puts "drive not mounted; execute: #{exec_string}"
      @ssh_session.exec! "mount /dev/vg-#{name}/lv-#{name} #{path}" do |ch, stream, data|
        if stream == :stderr && data != nil
          err = "Failed during mounting encrypted device"
          puts "#{err}: #{data}"
          puts "mount /dev/vg-#{name}/lv-#{name} #{path}"
          raise Exception.new(err)
        end
      end
    end
  end

  # Unconfigure the storage (using the crypto-helper used, e.g. #Help::DmCryptHelper)
  def undo_encryption(name, path)
    @crypto.undo_encryption(name, path)
  end

  # Unmount the specified path.
  def umount(path)
    exec_string = "umount #{path}"
    puts "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      puts "ssh_api.umount: returns #{data}"
    end
    !drive_mounted?(path)
  end
  
end
