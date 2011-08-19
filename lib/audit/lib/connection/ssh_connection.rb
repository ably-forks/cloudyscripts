require 'net/ssh'
require 'net/scp'
require 'net/sftp'
require 'logger'

class SshConnection
	@@logger = Logger.new(STDOUT)
	
	def initialize(parameters)
		raise "Need parameter :connection_params" unless parameters[:connection_params]
		
		if parameters[:logger] then
			@@logger = parameters[:logger]
		end

		@parameters = parameters[:connection_params]
		@parameters[:user] = 'root' unless @parameters[:user]
		raise "No target host specified" unless @parameters[:host]
	end

	# open the ssh connection to the remote host
	def open(&block)
		if @ssh_session && !@ssh_session.closed? then
			@@logger.warn("trying to open an already opened ssh connection")
			raise "trying to open an already opened ssh connection"
		end
		
		@@logger.info("opening ssh connection with parameters: " + @parameters.to_s)
	
		parameters = @parameters.clone()
		host = @parameters[:host]
		user = @parameters[:user]
		
		parameters.delete(:host)
		parameters.delete(:user)
		
		if @parameters[:keys] then
			@@logger.info("Starting SSH session with public key authentication")
		elsif @parameters[:key_data] then
			@@logger.info("Starting SSH session with public key authentication")
		elsif @parameters[:password] then
			@@logger.info("Starting SSH session with password authentication")
		else
			@@logger.error("No SSH authentication method found in parameters")
			raise "No authentication method found"
		end

		connected = false
		trials = 5
		while !connected and trials > 0
			begin
				@ssh_session = Net::SSH.start(host, user, parameters)
				connected = true
			rescue Exception => e
				@@logger.warn("connection attempt failed due to #{e.backtrace}")
			end
			trials -= 1
			if !connected
				sleep(20)
			end
		end
	
		if block then
			yield self
			close
		end
	end
	
	def close
		@ssh_session.close
	end
	
	def <<(command)
		exec(command)
	end

	# remote execute a command
	def exec(command, stdin = nil)
	  exit_status = 0 # define variable so that it will be available in the block at method scope
	  @ssh_session.open_channel do |ch|
	    @@logger.info("Executing command '#{command}'")
	    ch.exec(command) do|ch, success|

              if success then
	        @@logger.debug("Command sucessfully executed")
                ch.on_data() do|ch, data|
                  #process_stdout(data) unless data
                  @stdout_handler.call(data) unless @stdout_handler.nil? or data.nil?
                end
                ch.on_extended_data() do|ch, type, data|
                  @stderr_handler.call(data) unless @stderr_handler.nil? or data.nil?
                end
                ch.on_request "exit-status" do|ch, data|
                  exit_status = data.read_long unless data.nil?
                end
                ch.on_close do |ch|
                  @close_handler.call() unless @close_handler.nil?
                end
                ch.on_eof do |ch|
                  @close_handler.call() unless @close_handler.nil?
                end

                ch.send_data stdin if stdin
              else
	        @@logger.debug("")
                exit_status = 127
              end
            end
	    ch.wait
	  end
	
	  return exit_status
	end

	#XXX: new remote execute a command
	def exec_new(command, stdin = nil)
	  exit_status = 0 # define variable so that it will be available in the block at method scope
	  channel = @ssh_session.open_channel do |ch|
	    ch.exec(command) do|ch, success|

            if success then
	        @@logger.info("SshConnection: starts executing '#{command}'")
                ch.on_data() do|ch, data|
                  #process_stdout(data) unless data
                  @stdout_handler.call(data) unless @stdout_handler.nil? or data.nil?
                end
                ch.on_extended_data() do|ch, type, data|
                  @stderr_handler.call(data) unless @stderr_handler.nil? or data.nil?
                end
                ch.on_request "exit-status" do|ch, data|
                  exit_status = data.read_long unless data.nil?
	          @@logger.info("SshConnection.on_request: process terminated with exit-status: #{exit_status}")
	          if exit_status != 0
	            @@logger.error("SshConnection.on_request: Remote command execution failed with code: #{exit_status}")
	          end
                end
	        ch.on_request "exit-signal" do |ch, data|
	          @@logger.info("SshConnection.on_request: process terminated with exit-signal: #{data.read_string}")
	        end
                ch.on_close do |ch|
	          @@logger.info("SshConnection.on_close: remote end is closing!")
                  #@close_handler.call() unless @close_handler.nil?
                end
                ch.on_eof do |ch|
	          @@logger.info("SshConnection.on_eof: remote end is done sending data")
                  #@close_handler.call() unless @close_handler.nil?
                end
	        ch.on_open_failed do |ch, code, desc|
	          @@logger.info("SshConnection.on_open_failed: code=#{code} desc=#{desc}")
	        end
	        ch.on_process do |ch|
	          #@@logger.debug("SshConnection.on_process; send line-feed/sleep")
	          ch.send_data("\n")
	        end

                #ch.send_data stdin if stdin
            else
	        @@logger.debug("SshConnection: the remote command could not be invoked!")
                exit_status = 127
              end
            end
	    #ch.wait
	  end
	  channel.wait
	  return exit_status
	end

	
	#copy local file to remote path
	def copy_to_remote(local_file, remote_path)
		@ssh_session.scp.upload! local_file, remote_path
	end
	
	#copy remote file to local path
	def copy_from_remote(remote_file, local_path)
		begin
			@@logger.info { "Copying file from #{remote_file} to #{local_path}" }
			@ssh_session.scp.download!(remote_file, local_path)
			return true
		rescue => err
			@@logger.error { "SCP failed: #{err.message}" }
			@@logger.error { "\t #{err.backtrace}" }
		end
	end

  #write a string to a remote file
  def write_to_remote_file(string, remote_path)
    #filename = "/tmp/" + Random.srand().to_s() + ".sh"
    filename = "/tmp/" + Kernel::srand().to_s() + ".sh"
    File.open(filename, 'w') {|f| f.write(string)}
    copy_to_remote(filename, remote_path)
    File.delete(filename)
  end
	
	#delete remote file
	def delete_remote(remote_file)
		exec("rm #{remote_file}")
	end
	
	# copies remote file to local path and deletes remote file afterwards
	def move_from_remote(remote_file, local_path)
		copy_from_remote(remote_file, local_path)
		delete_remote(remote_file)
	end

  # hook a handler who is called on text on stdout.
	def on_stdout(&block)
		@stdout_handler = block
	end

  # hook a handler who is called on text on stderr
	def on_stderr(&block)
		@stderr_handler = block
	end

  # hook a handler who is called on connection close
	def on_close(&block)
		@close_handler = block
	end

  #if the connection is closed
	def closed?
		return @ssh_session.nil? || @ssh_session.closed?
	end

  # return a string representation of the connection
  def to_s()
    return "ssh:#{@parameters[:user]}@#{@parameters[:host]}"
  end

  def to_hash()
    return {
      :type => :CONNECTION,
      :subtype => :ssh,
      :user => @parameters[:user],
      :host => @parameters[:host]
    }
  end

  #force the connection to close
  def abort()
    if @ssh_session && !@ssh_session.closed? then
      #try to close connection gracefully
      @ssh_session.close
      # and if it won't, send out the hunter to bring in Snowwhite's heart after some time
      Thread.new do
        sleep 5
        @ssh_session.shutdown! unless @ssh_session.nil? || @ssh_session.closed?
      end
    end
  end
	
#	def SshConnection.finalize(id)
#		
#	end
end
