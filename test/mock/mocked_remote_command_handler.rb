# To change this template, choose Tools | Templates
# and open the template in the editor.

class MockedRemoteCommandHandler
  attr_accessor :drive_mounted, :logger, :open_ports, :use_sudo

  def initialize
    @open_ports = [80]
    @connected = false
    @drive_mounted = false
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::ERROR
  end

  def use_sudo
    puts "use sudo"
  end

  def disable_sudoers_requiretty
    puts "disable_sudoers_requiretty"
  end

  def enable_sudoers_requiretty
    puts "enable_sudoers_requiretty"
  end

  def get_root_device()
    #"dummy/root_device"
    "/dev/sda1"
  end

  # Get partition label
  def get_partition_device(part)
    "dummy/partition_device"
    "/dev/sdj1"
  end

  # Get device label
  def get_device_label(device)
    "dummy/device_label"
  end

  def get_device_label_ext(device, fs_type)
    "dummy/get_device_label_ext"
  end

  # Set device label
  def set_device_label(device, label)
    puts "set device label"
    true
  end

  # Set device label
  def set_device_label_ext(device, label, fs_type)
    puts "set device label ext"
    true
  end

  # Get filesystem type
  def get_root_fs_type()
    #"dummy/get_root_fs_type"
    "ext3"
  end

  # Get filesystem type
  def get_partition_fs_type(part)
    #"get_partition_fs_type"
    "ext3"
  end

  def is_port_open?(ip, port)
    puts "check for #{ip} on port #{port} => #{@open_ports.include?(port)}"
    return @open_ports.include?(port)
  end

  def connect(ip, user, keydata)
    if ip == nil || ip.strip.size == 0
      raise Exception.new("IP is empty")
    end
    if user == nil || user.strip.size == 0
      raise Exception.new("no username specified for ssh")
    end
    @logger.debug "mocked_ssh_api: connected to ip=#{ip} user=#{user} key_data=#{keydata}"
    @connected = true
  end

  def connect_with_keyfile(ip, key)
    if ip == nil || ip.strip.size == 0
      raise Exception.new("IP is empty")
    end
    @logger.debug "mocked_ssh_api: connected to ip=#{ip} keys=#{key}"
    @connected = true
  end

  def drive_mounted?(path)
    test_connected()
    @drive_mounted
  end

  def drive_mounted_as?(device, path)
    test_connected()
    @drive_mounted
  end

  def disconnect
    test_connected()
    @logger.debug "mocked_ssh_api: disconnected"
  end

  def install(software_package)
    test_connected()
    @logger.debug "mocked_ssh_api: install #{software_package}"
  end

  def tools_installed?(software_package)
    test_connected()
    @logger.debug "mocked_ssh_api: check_install #{software_package}"
    true
  end

  def encrypt_storage(name, password, mount_point, path)
    test_connected()
    @logger.debug "mocked_ssh_api: encrypt_storage #{name} #{password},#{mount_point},#{path}"
    #Create a dm-encrypted partition on the EBS volume:
    "sudo cryptsetup create dm-atrust /dev/sdd"
      #=> issue? you will be prompted for a passphrase – user a long, complex one – you won’t have to type it by hand anyway)
    #Create a new LVM PV (physical volume) on the encrypted partition:
    "sudo pvcreate /dev/mapper/dm-atrust"
    #Create a new LVM VG (volume group) on the LVM PV:
    "sudo vgcreate vg-atrust /dev/mapper/dm-atrust"
    #Create a new LVM LV (logical volume) on the LVM VG:
    "sudo lvcreate -n lv-atrust -L2G vg-atrust"
    #Create a new filesystem on the LVM LV:
    "sudo mkfs -t xfs /dev/vg-atrust/lv-atrust" #(you can use any filesystem, I just like XFS)
    #Mount and test our your encrypted volume:
    "sudo mount /dev/vg-atrust/lv-atrust /atrust"
    @drive_mounted = true
  end

  def storage_encrypted?(password, device, path)
    test_connected()
    @logger.debug "mocked_ssh_api: test_storage_encryption #{password},#{device},#{path}"
  end

  def activate_encrypted_volume(device, path)
    test_connected()
    @logger.debug "mocked_ssh_api: activate_encrypted_volume #{device},#{path}"
  end

  def undo_encryption(name, path)
    test_connected()
    @logger.debug "mocked_ssh_api: undo_encryption #{name} #{path}"
  end

  def mount(device, path)
    test_connected()
    @logger.debug "mocked_ssh_api: mount #{device} #{path}"
    @drive_mounted = true
  end

  def umount(path)
    test_connected()
    @logger.debug "mocked_ssh_api: umount #{path}"
    @drive_mounted = false
  end

  def create_filesystem(fs_type, volume)
    test_connected()
    e = "mocked_ssh_api: echo y >tmp.txt; mkfs -t #{fs_type} #{volume} <tmp.txt; rm -f tmp.txt"
    @logger.debug "#{e}"
  end

  def mkdir(path)
    test_connected()
    e = "mocked_ssh_api: mkdir #{path}"
    @logger.debug "#{e}"
  end

  def local_rcopy(source_path, dest_path, exclude_path = nil)
    test_connected()
    if exclude_path.nil? || exclude_path.empty? 
      e = "cp -Rpv #{source_path} #{dest_path}"
    else
      # only one level of exlusion
      #e = "for dir in $(ls #{source_path} | grep -v #{dest_path.split('/')[1]}); do cp -Rpv #{source_path}/$dir #{dest_path}/$dir; done"
      exclusion_regexp = exclude_path.gsub(' ', '|')
      e = "for dir in $(ls -d #{source_path}* | grep -E -v '#{exclusion_regexp}'); do cp -Rpv $dir #{dest_path}; done"
    end
    @logger.debug "#{e}"
  end

  def local_rsync(source_path, dest_path, exclude_path = nil)
    test_connected()
    ex = exclude_path == nil ? "" : "--exclude #{exclude_path}"
    e = "rsync -avHx #{ex} #{source_path} #{dest_path}"
    @logger.debug "#{e}"
  end

  def remote_rsync(keyfile, source_path, dest_ip, dest_user, dest_path)
    test_connected()
    e = "rsync -rlpgoDzq -e "+'"'+"ssh -o stricthostkeychecking=no -i #{keyfile}"+'"'+" #{source_path} root@#{dest_ip}:#{dest_path}"
    @logger.debug "going to execute #{e}"
  end

  def zip(source_path, destination_file)
    test_connected()
    e = "cd #{source_path}; zip #{destination_file}/*"
    @logger.debug "#{e}"
    [e]
  end

  def retrieve_os()
    "dummy-os.1.0.1"
  end

  def remote_execute(exec_string, push_data = nil, raise_exception = false)
    @logger.debug("remote execution of #{exec_string}")
  end

  def stdout_contains?(exec_string, search_string = "", push_data = nil)
    @logger.debug("remote execution (with stdout check) of #{exec_string}")
  end

  def file_exists?(path)
    test_connected()
    true
  end

  def file_size(file)
    @logger.debug("--- mock_remote_cmd_hdl: file_size")
    test_connected()
    e = "ls -lh #{file} | cut -d ' ' -f 5"
    @logger.debug("going to execute: #{e}")
  end

  def echo(data, file)
    test_connected()
    @logger.debug("echo #{data} > file")
  end

  def upload(ip, user, key_data, local_file, destination_file, timeout = 30)
    @logger.debug("upload file #{local_file} to #{user}@#{ip}:#{destination_file} [key_length = #{key_data.size}")
  end

  def local_dump_and_compress(source_device, target_filename)
    @logger.debug("--- mock_remote_cmd_hdl: local_dump_and_compress")
    test_connected()
    e = "dd if=#{source_device} | gzip > #{target_filename}"
    @logger.debug("going to execute: #{e}")
  end

  def local_decompress_and_dump(source_filename, target_device)
    @logger.debug("--- mock_remote_cmd_hdl: local_decompress_and_dump")
    test_connected()
    e = "gunzip -c #{source_filename} | dd of=#{target_device}"    
    @logger.debug("going to execute: #{e}")
  end

  def local_dump(source_device, target_filename)
    @logger.debug("--- mock_remote_cmd_hdl: local_dump")
    test_connected()
    e = "sh -c 'dd if=#{source_device} of=#{target_filename} bs=1M'"
    @logger.debug "going to execute #{e}" 
  end

  
  private

  def test_connected()
    if !@connected
      raise Exception.new("not connected")
    end
  end


end
