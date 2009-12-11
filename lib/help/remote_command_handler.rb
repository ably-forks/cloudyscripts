require 'rubygems'
require 'net/ssh'

class RemoteCommandHandler
  def initialize
    @crypto = DmCryptHelper.new #TODO: instantiate helpers for different tools
  end

  def self.file_exists?(ssh_session, path)
    result = true
    ssh_session.exec!("ls #{path}") do |ch, stream, data|
      if stream == :stderr
        result = false
      end
    end
    result
  end
  
  def connect(ip, keyfile)
    @ssh_session = Net::SSH.start(ip, 'root', :keys => [keyfile])
    @crypto.set_ssh(@ssh_session)
  end

  def disconnect
    @ssh_session.close
  end

  def install(software_package)
    @crypto.install()
  end

  def tools_installed?(software_package)
    @crypto.tools_installed?
  end

  def encrypt_storage(name, password, device, path)
    @crypto.encrypt_storage(name, password, device, path)
  end

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

  def activate_encrypted_volume(name, path)
    drive_mounted = drive_mounted?(path)
    puts "drive #{path} mounted? #{drive_mounted}"
    if !drive_mounted
      @ssh_session.exec! "mkdir #{path}"
      exec_string = "mount /dev/vg-#{name}/lv-#{name} #{path}"
      puts "drive not mounted; execute: #{exec_string}"
      @ssh_session.exec! "mount /dev/vg-#{name}/lv-#{name} #{path}" do |ch, stream, data|
        if stream == :stderr && !data.blank?
          err = "Failed during mounting encrypted device"
          puts "#{err}: #{data}"
          puts "mount /dev/vg-#{name}/lv-#{name} #{path}"
          raise Exception.new(err)
        end
      end
    end
  end

  def undo_encryption(name, path)
    @crypto.undo_encryption(name, path)
  end

  def umount(path)
    exec_string = "umount #{path}"
    puts "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      puts "ssh_api.umount: returns #{data}"
    end
    !drive_mounted?(path)
  end
  
end
