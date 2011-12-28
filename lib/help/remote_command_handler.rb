require 'rubygems'
require 'net/ssh'
require 'net/scp'
require 'timeout'

# Provides methods to be executed via ssh to remote instances.
class RemoteCommandHandler
  attr_accessor :logger, :ssh_session, :use_sudo
  def initialize()
    @logger = Logger.new(STDOUT)
    @use_sudo = false
  end

  # Checks for a given IP/port if there's a response on that port.
  def is_port_open?(ip, port)
    begin
      Timeout::timeout(5) do
        begin
          s = TCPSocket.new(ip, port)
          s.close
          return true
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          return false
        end
      end
    rescue Timeout::Error
      return false
    end
  end

  # Connect to the machine as root using a keyfile.
  # Params:
  # * ip: ip address of the machine to connect to
  # * keyfile: path of the keyfile to be used for authentication
  def connect_with_keyfile(ip, user_name, keyfile, timeout = 30)
    @use_sudo = false
    @ssh_session = Net::SSH.start(ip, user_name, :keys => [keyfile], :timeout => timeout, :verbose => :warn)
    @use_sudo = true unless user_name.strip == 'root'
  end

  # Connect to the machine as root using keydata from a keyfile.
  # Params:
  # * ip: ip address of the machine to connect to
  # * user: user name
  # * key_data: key_data to be used for authentication
  def connect(ip, user, key_data, timeout = 30)
    @use_sudo = false
    @ssh_session = Net::SSH.start(ip, user, :key_data => [key_data], :timeout => timeout, :verbose => :warn)
    @use_sudo = true unless user.strip == 'root'
  end

  # Disconnect the current handler
  def disconnect
    @ssh_session.close
  end

  # Check if the path/file specified exists
  def file_exists?(path)
    remote_execute("ls #{path}")
  end

  # Returns the result of uname -a (Linux)
  def retrieve_os()
    get_output("uname -r").strip
  end

  # Get root partition label
  def get_root_device()
    #get_output("cat /etc/mtab | grep -E '[[:blank:]]+\/[[:blank:]]+' | cut -d ' ' -f 1").strip
    get_output("mount | grep -E '[[:blank:]]+\/[[:blank:]]+' | cut -d ' ' -f 1").strip
  end

  # Get partition label
  def get_partition_device(part)
    #get_output("cat /etc/mtab | grep -E '[[:blank:]]+" + "#{part}" + "[[:blank:]]+' | cut -d ' ' -f 1").strip
    get_output("mount | grep -E '[[:blank:]]+" + "#{part}" + "[[:blank:]]+' | cut -d ' ' -f 1").strip
  end

  # Get device label
  def get_device_label(device)
    get_output("e2label #{device}").strip
  end

  # Get device label
  def get_device_label_ext(device, fs_type)
    if fs_type.eql?("xfs")
      cmd = "xfs_admin -l #{device} | sed -r -e 's/^label[[:blank:]]*=[[:blank:]]*\"(.*)\"$/\\1/'"
    else
      cmd = "e2label #{device}"
    end
    get_output(cmd).strip
  end

  # Set device label
  def set_device_label(device, label)
    remote_execute("e2label #{device} #{label}", nil, false)
  end

  # Set device label
  def set_device_label_ext(device, label, fs_type)
    if fs_type.eql?("xfs")
      cmd = "xfs_admin -L #{label} #{device}"
    else
      cmd = "e2label #{device} #{label}"
    end
    remote_execute(cmd, nil, false)
  end

  # Get filesystem type
  def get_root_fs_type()
    get_output("cat /etc/mtab | grep -E '[[:blank:]]+\/[[:blank:]]+' | cut -d ' ' -f 3").strip
  end

  # Get filesystem type
  def get_partition_fs_type(part)
    get_output("cat /etc/mtab | grep -E '[[:blank:]]+" + "#{part}" + "[[:blank:]]+' | cut -d ' ' -f 3").strip
  end

  # Installs the software package specified.
  def install(software_package)
    e = "yum -yq install #{software_package}"
    yum = remote_execute(e)
    if !yum
      @logger.info("yum installation failed; try apt-get")
      e = "apt-get -yq install #{software_package}"
      apt = remote_execute(e)
      @logger.info("apt=get installation? #{apt}")
    end
  end

  # Checks if the software package specified is installed.
  def tools_installed?(software_package)
    exec_string = "which #{software_package}"
    stdout = []
    stderr = []
    result = remote_exec_helper(exec_string, stdout, stderr)
    return result == true && stdout.size > 0
  end

  def create_filesystem(fs_type, volume)
    e = "mkfs -t #{fs_type} #{volume}"
    #remote_execute(e, "y") #TODO: quiet mode?
    remote_execute(e, "y", false)
  end

  def mkdir(path)
    e = "mkdir #{path}"
    remote_execute(e, nil, true)
  end

  def mount(device, path)
    e = "mount #{device} #{path}"
    remote_execute(e, nil, true)
  end

  # Checks if the drive on path is mounted
  def drive_mounted?(path)
    #check if drive mounted
    drive_found = stdout_contains?("mount", "on #{path} type")
    if drive_found
      return file_exists?(path)
    else
      @logger.debug "not mounted (since #{path} non-existing)"
      false
    end
  end

  # Checks if the drive on path is mounted with the specific device
  def drive_mounted_as?(device, path)
    #check if drive mounted
    stdout_contains?("mount", "#{device} on #{path} type")
  end

  # Unmount the specified path.
  def umount(path)
    exec_string = "umount #{path}"
    remote_execute(exec_string)
    !drive_mounted?(path)
  end

  # Copy directory using basic cp
  # exclude_path: a space separated list of directory
  def local_rcopy(source_path, dest_path, exclude_path = nil)
    e = ""
    if exclude_path.nil? || exclude_path.empty? 
      e = "cp -Rpv #{source_path} #{dest_path}"
    else
      # only one level of exclusion
      exclusion_regexp = exclude_path.gsub(' ', '|')
      e = "for dir in $(ls -d #{source_path}* | grep -E -v '#{exclusion_regexp}'); do cp -Rpv $dir #{dest_path}; done;"
    end
    @logger.debug "going to execute #{e}"
    remote_exec_helper(e, nil, nil, false)
  end

  # Copy directory using options -avHx
  def local_rsync(source_path, dest_path, exclude_path = nil)
    exclude = ""
    if exclude_path != nil
      exclude = "--exclude #{exclude_path}"
    end
    e = "rsync -avHx #{exclude} #{source_path} #{dest_path}"
    @logger.debug "going to execute #{e}"
    remote_exec_helper(e, nil, nil, true) #TODO: handle output in stderr?
  end

  # Rsync directory via an ssh-tunnel.
  def remote_rsync_old(keyfile, source_path, dest_ip, dest_path)
    e = "rsync -rlpgoDzq -e "+'"'+"ssh -o stricthostkeychecking=no -i #{keyfile}"+'"'+" #{source_path} root@#{dest_ip}:#{dest_path}"
    @logger.debug "going to execute #{e}"
    remote_exec_helper(e, nil, nil, false) #TODO: handle output in stderr?
  end

  # Disable 'Defaults requiretty' option in sudoers file
  def disable_sudoers_requiretty()
    e = "sed -r -e \'s/^(Defaults[[:blank:]]+requiretty)$/# \\1/\' -i /etc/sudoers"
    @logger.debug "going to execute '#{e}'"
    status = remote_exec_helper(e, nil, nil, true)
    if status != true
      raise Exception.new("disabling 'requiretty' from sudoers failed with status: #{status}")
    end
  end

  # Enable 'Defaults requiretty' option in sudoers file
  def enable_sudoers_requiretty()
    e = "sed -r -e \'s/^#[[:blank:]]*(Defaults[[:blank:]]+requiretty)$/\\1/\' -i /etc/sudoers"
    @logger.debug "going to execute '#{e}'"
    status = remote_exec_helper(e, nil, nil, true)
    if status != true
      raise Exception.new("enabling 'requiretty' from sudoers failed with status: #{status}")
    end
  end

  def remote_rsync(keyfile, source_path, dest_ip, dest_user, dest_path)
    e = "rsync -rlpgoDzq --rsh 'ssh -o stricthostkeychecking=no -i #{keyfile}' --rsync-path='sudo rsync'"+
          " #{source_path} #{dest_user}@#{dest_ip}:#{dest_path}"
    @logger.debug "going to execute #{e}"
    status = remote_exec_helper(e, nil, nil, true) #TODO: handle output in stderr?
    if status != true
      raise Exception.new("rsync bewteen source and target servers failed with status: #{status}")
    end
  end

  # Copy directory via an ssh-tunnel.
  def scp(keyfile, source_path, dest_ip, dest_user, dest_path)
    e = "scp -Cpqr -o stricthostkeychecking=no -i #{keyfile} #{source_path} #{dest_user}@#{dest_ip}:#{dest_path}"
    @logger.debug "going to execute #{e}"
    remote_exec_helper(e, nil, nil, false) #TODO: handle output in stderr?
  end

  # dump and compress a device in a file locally
  def local_dump_and_compress(source_device, target_filename)
    e = "sh -c 'dd if=#{source_device} | gzip > #{target_filename}'"
    @logger.debug "going to execute #{e}" 
    status = remote_exec_helper(e, nil, nil, true)
  end

  # idecompress and a file to a device locally
  def local_decompress_and_dump(source_filename, target_device)
    e = "sh -c 'gunzip -c #{source_filename} | dd of=#{target_device}'"
    @logger.debug "going to execute #{e}" 
    status = remote_exec_helper(e, nil, nil, true)
  end

  # Zip the complete contents of the source path into the destination file.
  # Returns the an array with stderr output messages.
  def zip(source_path, destination_file)
    begin
      exec = "cd #{source_path}; zip -ryq #{destination_file} *"
      stderr = []
      get_output(exec, nil, nil, stderr)
      return stderr
    rescue Exception => e
      raise Exception.new("zip failed due to #{e.message}")
    end
  end

  def echo(data, file)
    exec = "echo #{data} > #{file}"
    @logger.debug "going to execute #{exec}"
    remote_execute(exec, nil, true)
    if !file_exists?(file)
      raise Exception.new("file #{file} could not be created")
    end
  end

  # Executes the specified #exec_string on a remote session specified.
  # When #push_data is specified, the data will be used as input for the
  # command and thus allow to respond in advance to commands that ask the user
  # something.
  # The method will return true if nothing was written into stderr, otherwise false.
  # When #raise_exception is set, an exception will be raised instead of
  # returning false.
  def remote_execute(exec_string, push_data = nil, raise_exception = false)
    exec_string = "sh -c 'echo #{push_data} >tmp.txt; #{exec_string} <tmp.txt; rm -f tmp.txt'" unless push_data == nil
    stdout = []
    stderr = []
    result = remote_exec_helper(exec_string, stdout, stderr, true)
    #dump stdout in case of error
    if result == false
      em = "RemoteCommandHandler: #{exec_string} lead to stdout message: #{stdout.join().strip}"
      @logger.info(em) unless stdout.size == 0
    end
    em = "RemoteCommandHandler: #{exec_string} lead to stderr message: #{stderr.join().strip}"
    @logger.info(em) unless stderr.size == 0
    raise Exception.new(em) unless result == true || raise_exception == false
    result
  end

  # Executes the specified #exec_string on a remote session specified as #ssh_session
  # and logs the command-output into the specified #logger. When #push_data is
  # specified, the data will be used as input for the command and thus allows
  # to respond in advance to commands that ask the user something. If the output
  # in stdout contains the specified #search_string, the method returns true
  # otherwise false. Output to stderr will be logged.
  def stdout_contains?(exec_string, search_string = "", push_data = nil)
    exec_string = "echo #{push_data} >tmp.txt; #{exec_string} <tmp.txt; rm -f tmp.txt" unless push_data == nil
    stdout = []
    stderr = []
    remote_exec_helper(exec_string, stdout, stderr)
    @logger.info("RemoteCommandHandler: #{exec_string} lead to stderr message: #{stderr.join().strip}") unless stderr.size == 0
    stdout.join().include?(search_string)
  end

  # Executes the specified #exec_string on a remote session specified as #ssh_session.
  # When #push_data is specified, the data will be used as input for the command and thus allows
  # to respond in advance to commands that ask the user something. It returns
  # stdout. When #stdout or #stderr is specified as arrays, the respective output is
  # also written into those arrays.
  def get_output(exec_string, push_data = nil, stdout = [], stderr = [])
    exec_string = "echo #{push_data} >tmp.txt; #{exec_string} <tmp.txt; rm -f tmp.txt" unless push_data == nil
    stdout = []
    stderr = []
    remote_exec_helper(exec_string, stdout, stderr, true)
    stdout.join()
  end

  def upload(ip, user, key_data, local_file, destination_file, timeout = 60)
    Timeout::timeout(timeout) {
      Net::SCP.start(ip, user, {:key_data => [key_data], :timeout => timeout}) do |scp|
        scp.upload!(local_file, destination_file)
      end
    }
  end

  private

  # Executes the specified #exec_string on the opened remote session.
  # The method will return true if nothing was written into stderr, otherwise false.
  # All stdout-data is written into #stdout, all stderr-data is written into #stderr
  def remote_exec_helper(exec_string, stdout = [], stderr = [], debug = false)
    result = true
    sudo = (@use_sudo ? "sudo " : "")
    the_channel = @ssh_session.open_channel do |channel|
      if sudo
        channel.request_pty do |ch, success|
          if success
            @logger.debug("pty successfully obtained")
          else
            @logger.debug("could not obtain pty")
          end
        end
      end
      channel.exec("#{sudo}#{exec_string}") do |ch, success|
        if success
          @logger.debug("RemoteCommandHandler: starts executing '#{sudo}#{exec_string}'") if debug
          ch.on_data() do |ch, data|
            stdout << data unless data == nil || stdout == nil
          end
          ch.on_extended_data do |ch, type, data|
            stderr << data unless data == nil || stderr == nil
            #result = false
          end
          ch.on_eof do |ch|
            @logger.debug("RemoteCommandHandler.on_eof: remote end is done sending data") if debug
          end
          ch.on_close do |ch|
            @logger.debug("RemoteCommandHandler.on_close: remote end is closing!") if debug
          end
          ch.on_open_failed do |ch, code, desc|
            @logger.debug("RemoteCommandHandler.on_open_failed: code=#{code} desc=#{desc}") if debug
          end
          ch.on_process do |ch|
            @logger.debug("RemoteCommandHandler.on_process; send line-feed/sleep") if debug
            sleep(1)
            ch.send_data("\n")
          end
          ch.on_request "exit-status" do |ch, data|
            returned_code = data.read_long
            @logger.debug("process terminated with exit-status: #{returned_code}")
            if returned_code != 0
              @logger.error("Remote command execution failed with code: #{returned_code}")
              result = false
            end
          end
          ch.on_request "exit-signal" do |ch, data|
            @logger.debug("process terminated with exit-signal: #{data.read_string}")
          end       
        else
          stderr << "the remote command could not be invoked!" unless stderr == nil
          result = false
        end
      end
    end
    the_channel.wait
    result
  end

end
