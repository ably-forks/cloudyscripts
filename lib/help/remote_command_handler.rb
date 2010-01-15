require 'rubygems'
require 'net/ssh'

# Provides methods to be executed via ssh to remote instances.
class RemoteCommandHandler
  attr_accessor :logger, :ssh_session
  def initialize
    @logger = Logger.new(STDOUT)
  end

  # Connect to the machine as root using a keyfile.
  # Params:
  # * ip: ip address of the machine to connect to
  # * keyfile: path of the keyfile to be used for authentication
  def connect_with_keyfile(ip, keyfile)
    @ssh_session = Net::SSH.start(ip, 'root', :keys => [keyfile])
  end

  # Connect to the machine as root using keydata from a keyfile.
  # Params:
  # * ip: ip address of the machine to connect to
  # * user: user name
  # * key_data: key_data to be used for authentication
  def connect(ip, user, key_data)
    @ssh_session = Net::SSH.start(ip, user, :key_data => [key_data])
  end

  # Disconnect the current handler
  def disconnect
    @ssh_session.close
  end

  # Check if the path/file specified exists
  def file_exists?(path)
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, "ls #{path}")
  end

  # Returns the result of uname -a (Linux)
  def retrieve_os()
    RemoteCommandHandler.get_output(@ssh_session, "uname -r").strip
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

  def create_filesystem(fs_type, volume)
    e = "mkfs -t #{fs_type} #{volume}"
    RemoteCommandHandler.remote_execute(@ssh_session, @logger, e, "y") #TODO: quiet mode?
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
    drive_found = RemoteCommandHandler.stdout_contains?(@ssh_session, @logger, "mount", "on #{path} type")
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
    RemoteCommandHandler.stdout_contains?(@ssh_session, @logger, "mount", "#{device} on #{path} type")
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

  # Executes the specified #exec_string on a remote session specified as #ssh_session
  # and logs the command-output into the specified #logger. When #push_data is
  # specified, the data will be used as input for the command and thus allows
  # to respond in advance to commands that ask the user something.
  # The method will return true if nothing was written into stderr, otherwise false.
  # When #raise_exception is set, an exception will be raised instead of
  # returning false.
  def self.remote_execute(ssh_session, logger, exec_string, push_data = nil, raise_exception = false)
    logger.debug("RemoteCommandHandler: going to execute #{exec_string}")
    result = true
    exec_string = "echo #{push_data} >tmp.txt; #{exec_string} <tmp.txt; rm -f tmp.txt" unless push_data == nil
    output = ""
    ssh_session.exec(exec_string) do |ch, stream, data|
      output += data unless data == nil
      if stream == :stderr && data != nil
        result = false
      end
    end
    ssh_session.loop
    logger.info output unless logger == nil
    raise Exception.new("RemoteCommandHandler: #{exec_string} lead to stderr message: #{output}") unless result == true || raise_exception == false
    result
  end

  # Executes the specified #exec_string on a remote session specified as #ssh_session
  # and logs the command-output into the specified #logger. When #push_data is
  # specified, the data will be used as input for the command and thus allows
  # to respond in advance to commands that ask the user something. If the output
  # in stdout contains the specified #search_string, the method returns true
  # otherwise false. Output to stderr will be logged.
  def self.stdout_contains?(ssh_session, logger, exec_string, search_string = "", push_data = nil)
    logger.debug("RemoteCommandHandler: going to execute #{exec_string}")
    stdout = []
    stderr = []
    exec_string = "echo #{push_data} >tmp.txt; #{exec_string} <tmp.txt; rm -f tmp.txt" unless push_data == nil
    ssh_session.exec(exec_string) do |ch, stream, data|
      if stream == :stdout && data != nil
        stdout << data
      end
      if stream == :stderr && data != nil
        stderr << data
      end
    end
    ssh_session.loop
    logger.info("RemoteCommandHandler: #{exec_string} lead to stderr message: #{stderr.join("\n")}") unless stderr.size == 0
    stdout.join("\n").include?(search_string)
  end

  # Executes the specified #exec_string on a remote session specified as #ssh_session.
  # When #push_data is specified, the data will be used as input for the command and thus allows
  # to respond in advance to commands that ask the user something. It returns
  # stdout. When #stdout or #stderr is specified as arrays, the respective output is
  # also written into those arrays.
  def self.get_output(ssh_session, exec_string, push_data = nil, stdout = [], stderr = [])
    exec_string = "echo #{push_data} >tmp.txt; #{exec_string} <tmp.txt; rm -f tmp.txt" unless push_data == nil
    ssh_session.exec(exec_string) do |ch, stream, data|
      if stream == :stdout && data != nil
        stdout << data
      end
      if stream == :stderr && data != nil
        stderr << data
      end
    end
    ssh_session.loop
    stdout.join("\n")
  end


end
