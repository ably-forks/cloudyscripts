require 'net/ssh'
require 'logger'
require 'tempfile'
#require ssh-keygen command line program

class SSH_Utils
	
	public
	def initialize(options)
		if options[:logger] then
			@logger = options[:logger]
		else
			@logger = Logger.new(STDOUT)
		end
	end
	
	# Try user names from a list an return the user name that suceeded or nil.
	# Ignores host key match failures by default (set paranoid option in ssh_options
	# to change).
	#
	# @param host Host name of the server to try SSH login on
	# @param ssh_options The set of SSH options to use (conforming to the net-ssh package)
	#		This should contain the key or password used for logon.
	# @param possible_usernames An array of possible user names
	# @param timeout Maximum number of seconds each user name should be tried before giving up
	# @return The user name that logged in as String or nil
	public
	def guess_username(host, ssh_options, possible_usernames, timeout = 5)
		ssh_options = {:paranoid => false}.merge(ssh_options)
		possible_usernames.each do|username|
			begin
				timeout(timeout) do
					Net::SSH.start(host, username, ssh_options) do|conn|
						output = conn.exec!("id --user --name")
						if output.strip() == username then
							@logger.info {"Found user name '#{username}'\n"}
							return username
						else
							@logger.debug {"User name '#{username}' logs in but does not execute commands\n"} 
						end
					end
				end
			rescue Net::SSH::AuthenticationFailed => ex
				@logger.debug {"Authentication with user name '#{username}' failed\n"}
			rescue Timeout::Error => err
				@logger.debug {"Authentication with user name '#{username}' timed out\n"}
			end
		end
		
		return nil
	end
	
	# Wait for a server to be online.
	# @param host The host name to poll for a service.
	# @param port The service port to poll.
	# @param interval The wait time between two connection tries in seconds
	# @param max_retries The maximum number of connection retries
	# @return :OK if server is reachable, :CONNECTION_REFUSED if the maximum number of retries was reached and the connection was refused,
	#		or :TIMED_OUT if either the overall timeout was reached or the maximum number of retries was reached and the connection timed out.
	#		May also return :UNKNOWN_ERROR on unknown error.
	def wait_for_server(host, port = 22, interval = 20, max_retries = 5)
		for tries in 0 ... max_retries
			begin
				sock = TCPSocket.new(host, port)
				return :OK
			rescue Errno::ECONNREFUSED => ex
				return :CONNECTION_REFUSED if tries >= max_retries - 1
				@logger.debug {"Connection timed out, apparently server has not finished booting yet ... waiting #{interval}s\n"}
				sleep interval
			rescue Errno::ETIMEDOUT => ex
				return :TIMED_OUT if tries >= max_retries - 1
				@logger.debug {"Connection timed out, apparently server has not finished booting yet ... waiting #{interval}s\n"}
				sleep interval
			rescue Errno::EHOSTUNREACH => err
				return :TIMED_OUT if tries >= max_retries - 1
				@logger.debug {"No route to host, routes have not yet been set up ... waiting #{interval}s\n"}
				sleep interval
			end
		end
		
		return :UNKNOWN_ERROR
	end
	
	# Try to find a method to elevate privileges
	# Currently this tests only if the user is already root or privileges can be obtained with sudo.
	# Ignores host key match failures by default (set paranoid option in ssh_options
	# to change).
	#
	# @param host The remote SSH server.
	# @param username The username to log into the server.
	# @param ssh_options A hash of ssh options that is passed to the net/ssh module
	# @return :ALREADY_ROOT if the user already has root privileges, :SUDO if privileges can be elevated
	#		with 'sudo -n', or :NONE if no method for elevating privileges has been found.
	public
	def find_root_method(host, username, ssh_options)
		ssh_options = {:paranoid => false}.merge(ssh_options)
		Net::SSH.start(host, username, ssh_options) do|conn|
			output = conn.exec!("id --user 2>/dev/null")
			return :ALREADY_ROOT if output.strip() == "0"
			
			output = conn.exec!("sudo -n id --user 2>/dev/null")
			return :SUDO if output && output.strip() == "0"
		end
		
		return :NONE
	end
	
	public
	def get_root_prefix(host, username, ssh_options)
		root_method = find_root_method(host, username, ssh_options)
		
		case root_method
		when :NONE then return nil
		when :SUDO then return "sudo -H -n "
		when :ALREADY_ROOT then return ""
		else return nil
		end
	end
	
	# Get the public OpenSSH key from a private one
	# @param private_key The private key file as String
	# @param key_name Name of the key as String; optional
	# @return The private key in OpenSSH format
	public
	def get_public_key(private_key, key_name = "")
		return (`ssh-keygen -y -f #{private_key}`.strip() + " " + key_name).strip()
	end
	
	# Get the SSH key in standard SSH format from the OpenSSH format
	# @param openssh_key Key in OpenSSH format as string
	# @return Key in SSH (RFC) format as string
	def convert_to_ssh(openssh_key)
		tempfile = Tempfile.new('convert_')
		tempfile << openssh_key; tempfile.flush()
		
		ssh_key = `ssh-keygen -e -f #{tempfile.path()}`
		tempfile.close!()
		
		return ssh_key
	end
	
	# Enable root login on a remote SSH server by adding the public key and changing 
	# the server's configuration.
	# Ignores host key match failures by default (set paranoid option in ssh_options
	# to change).
	
	# @param host The remote SSH server
	# @param username The username to use for login
	# @param ssh_options The hash of ssh options used by net-ssh
	# @param public_key The public key to add to the authorized_keys file of root
	public
	def enable_root_login(host, username, ssh_options, public_key)
		ssh_options = {:paranoid => false}.merge(ssh_options)
		root_prefix = get_root_prefix(host, username, ssh_options)
		return if root_prefix.nil?()
		
		Net::SSH.start(host, username, ssh_options) do|conn|
			conn.exec!(root_prefix + "sh -c 'grep -v PermitRootLogin /etc/ssh/sshd_config > /tmp/sshd_config; echo \"PermitRootLogin without-password\" >> /tmp/sshd_config; mv /tmp/sshd_config /etc/ssh/sshd_config'")
			conn.exec!(root_prefix + "kill -SIGHUP $( ps -A -o pid -o cmd | grep /usr/sbin/sshd | grep -v grep | awk '{print $1}')")
		end
		
		Net::SSH.start(host, username, ssh_options) do|conn|
			conn.exec!(root_prefix + "sh -c 'echo \"#{public_key}\" > ${HOME}/.ssh/authorized_keys'") 
		end
	end
	
	# Create a new layer 3 tunnel to the SSH server
	# This method must be run with root privileges and needs also direct root access on the target machine.
	# Thus no username is required in the parameters, as it will always be 'root'.
	# Ignores host key match failures by default (set paranoid option in ssh_options
	# to change).
	#
	# @param host SSH server address as String.
	# @param private_key_file Path to the private key file that is used to authentify as root as String.
	# @param local_tun_num Number of the local tun interface that should be used as Integer.
	# @param remote_tun_num Number of the remote tun interface that should be used as Integer.
	# @param local_ip IP address that will be given to the local tun interface. Must be in the same /24 subnet as the <code>remote_ip</code>. String,
	# @param remote_ip IP address that will be given to the remote tun interface. Must be in the same /24 subnet as the <code>local_ip</code>. String.
	# @param ssh_options Any SSH options other than the private key file that should be passed on to net-ssh in its hash format.
	# @return A hash with the tunnel parameters. Most notably :success is a boolean that is set to <code>true</code> if the tunnel is established
	#		successfully.
	public
	def start_tunnel(host, private_key_file, local_tun_num = 0, remote_tun_num = 0, local_ip = "172.16.0.1", remote_ip = "172.16.0.2", ssh_options = {})
		username = 'root' # tunneling only works with root user, so assume root here
		result = false
		ssh_tunnel_process = "bla" # just any value to initialize the variable and assign the scope
		
		# change ssh server configuration to permit tunneling
		Net::SSH.start(host, username, {:keys => [private_key_file], :paranoid => false}.merge(ssh_options)) do|conn|
			conn.exec!("grep -v PermitTunnel /etc/ssh/sshd_config > /tmp/sshd_config; echo \"PermitTunnel yes\" >> /tmp/sshd_config; mv /tmp/sshd_config /etc/ssh/sshd_config")
			conn.exec!("kill -SIGHUP $( ps -A -o pid -o cmd | grep /usr/sbin/sshd | grep -v grep | awk '{print $1}')")
		end
		
		@logger.debug {"Modified SSH server configuration for tunneling"}
		
		# open the tunnel and configure
		Net::SSH.start(host, username, {:keys => [private_key_file], :paranoid => false}.merge(ssh_options)) do|conn|
			
			ssh_tunnel_cmd = "ssh -NT -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=30 -w #{local_tun_num}:#{remote_tun_num} -i #{private_key_file} #{username}@#{host}"
			@logger.debug {"LOCAL: Starting tunneling SSH process: '#{ssh_tunnel_cmd}'"}
			ssh_tunnel_process = IO.popen(ssh_tunnel_cmd)
			# configure tunneling interfaces
			sleep(3) #some delay because otherwise tun devices are not configured correctly
			remote_tun_conf_cmd = "ifconfig tun#{remote_tun_num} #{local_ip} #{remote_ip} netmask 255.255.255.0 2>/dev/null 1>/dev/null"
			@logger.debug {"REMOTE: configuring tun interface: '#{remote_tun_conf_cmd}'"}
			conn.exec!(remote_tun_conf_cmd)
			
			local_tun_conf_cmd = "ifconfig tun#{local_tun_num} #{remote_ip} #{local_ip} netmask 255.255.255.0 2>/dev/null 1>/dev/null"
			@logger.debug {"LOCAL: configuring tun interface: '#{local_tun_conf_cmd}'"}
			system(local_tun_conf_cmd)
			# check that the connection works
			ping_cmd = "ping -c1 #{remote_ip} 2>/dev/null 1>/dev/null"
			@logger.debug {"LOCAL: pinging remote interface: '#{ping_cmd}'"}
			result = system(ping_cmd)
		end
		
		return {:success => result, 
		        :tunnel_server_pid => ssh_tunnel_process.pid(), 
		        :remote_ip => remote_ip, 
		        :local_ip => local_ip, 
		        :remote_tun_interface => "tun#{remote_tun_num}",
		        :local_tun_interface => "tun#{local_tun_num}"}
	end
	
	# Stop a tunnel.
	# This will stop the tunnel by killing the corresponding SSH process.
	#
	# @param tunnel_hash Hash as returned by start_tunnel. The :tunnel_server_pid will be used to stop the process.
	public 
	def stop_tunnel(tunnel_hash)
		# first try to end gently
		begin
			Process::kill('TERM', tunnel_hash[:tunnel_server_pid])
		rescue => err
		end
		#check if it really ended
		begin
			Process::kill('TERM', tunnel_hash[:tunnel_server_pid])
		rescue Errno::ESRCH => err
			return
		rescue => err
		end
		
		#if not, wait a second and then try the hard way
		sleep(1)
		begin
			Process::kill('KILL', tunnel_hash[:tunnel_server_pid])
		rescue Errno::ESRCH => err
			return
		rescue => err
		end
	end
	
	public
	def parse_nmap_ssh_keydata(keydata)
		line_type = :fingerprint_line
		current_key = nil
		keys = []
		keydata.each_line do|line|
			if line_type == :fingerprint_line then
				match = /^([0-9]+) ([0-9a-f:]+) (\([A-Z0-9]+\))$/.match(line)
				if match && !current_key.nil?() then
					#something is desynchronized, skip the key
					puts "Unexpected input at ssh host key data: '#{keydata}'"
					break
				elsif match && current_key.nil?() then
					current_key = { :length => match[1], :fingerprint => match[2], :type => match[3] }
				else
					puts "Unexpected line at ssh host key data, expected fingerprint data: '#{keydata}'"
					break
				end
				line_type = :key_line
			else
				match = /^([a-z0-9_-]+) ([A-Za-z0-9+\/=]+)$/.match(line)
				if match && current_key.nil?() then
					puts "Unexpected line at ssh host key data, expected key data: '#{keydata}'"
					break
				elsif match && !current_key.nil?() then
					current_key[:ssh_type] = match[1]
					current_key[:key] = match[2]
					keys << current_key
					current_key = nil
				else
					puts "Unexpected input at ssh host key data, expected key data: '#{keydata}'"
					break
				end
				line_type = :fingerprint_line
			end
		end
		return keys
	end
end
