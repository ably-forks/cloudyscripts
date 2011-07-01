require 'socket'
require 'timeout'
require 'openssl'

require 'net/ssh/transport/session'


module Net; module SSH; module Transport
	class Algorithms
		attr_reader :server_data
		attr_reader :key_data
		
		# Instantiates one of the Transport::Kex classes (based on the negotiated
      # kex algorithm), and uses it to exchange keys. Then, the ciphers and
      # HMACs are initialized and fed to the transport layer, to be used in
      # further communication with the server.
      def exchange_keys
        debug { "exchanging keys" }

        algorithm = Kex::MAP[kex].new(self, session,
          :client_version_string => Net::SSH::Transport::ServerVersion::PROTO_VERSION,
          :server_version_string => session.server_version.version,
          :server_algorithm_packet => @server_packet,
          :client_algorithm_packet => @client_packet,
          :need_bytes => kex_byte_requirement,
          :logger => logger)
        result = algorithm.exchange_keys
		  
		  #added by jonas
		  result[:type] = host_key()
		  @key_data = result

        secret   = result[:shared_secret].to_ssh
        hash     = result[:session_id]
        digester = result[:hashing_algorithm]

        @session_id ||= hash

        key = Proc.new { |salt| digester.digest(secret + hash + salt + @session_id) }
        
        iv_client = key["A"]
        iv_server = key["B"]
        key_client = key["C"]
        key_server = key["D"]
        mac_key_client = key["E"]
        mac_key_server = key["F"]

        parameters = { :iv => iv_client, :key => key_client, :shared => secret,
          :hash => hash, :digester => digester }
        
        cipher_client = CipherFactory.get(encryption_client, parameters.merge(:encrypt => true))
        cipher_server = CipherFactory.get(encryption_server, parameters.merge(:iv => iv_server, :key => key_server, :decrypt => true))

        mac_client = HMAC.get(hmac_client, mac_key_client)
        mac_server = HMAC.get(hmac_server, mac_key_server)

        session.configure_client :cipher => cipher_client, :hmac => mac_client,
          :compression => normalize_compression_name(compression_client),
          :compression_level => options[:compression_level],
          :rekey_limit => options[:rekey_limit],
          :max_packets => options[:rekey_packet_limit],
          :max_blocks => options[:rekey_blocks_limit]

        session.configure_server :cipher => cipher_server, :hmac => mac_server,
          :compression => normalize_compression_name(compression_server),
          :rekey_limit => options[:rekey_limit],
          :max_packets => options[:rekey_packet_limit],
          :max_blocks  => options[:rekey_blocks_limit]

        @initialized = true
      end
	end
end; end; end

module Net; module SSH; module Authentication; module Methods
	class None < Abstract
		def authenticate(next_service, username = "dummy", password = nil)
			send_message(userauth_request(username, next_service, "none"))
			message = session.next_message
				
			case message.type
				when USERAUTH_SUCCESS
					debug { "login with 'none' suceeded" }
					return true
				when USERAUTH_FAILURE
					debug { "login with 'none' failed" }
					return false
			end
		end
	end
end; end; end; end

module SSH_Fingerprint2
	# Read all interesting properties from a key and save them in a map
	def self.read_key(key)
		buffer = Net::SSH::Buffer.new(key.to_blob())
		type = buffer.read_string()
		
		case type
			when "ssh-rsa"
				e = buffer.read_string()
				n = buffer.read_string()
				size = (n.length() - 1) * 8
			when "ssh-dss"
				p = buffer.read_string()
				q = buffer.read_string()
				g = buffer.read_string()
				pub_key = buffer.read_string()
				size = (pub_key.length() - 1) * 8
		end
				
		
		return {#:key => key, 
				:blob => [key.to_blob()].pack("m").strip(), 
				:fingerprint => key.fingerprint(),
				:size => size,
				:type => key.ssh_type()}
	end
		
		
	public
	def self.fingerprint(host, port = 22, timeout = 10)
		results = {:host => host, :port => port, :timestamp => Time.now(), :status => :OK}
		logger = Logger.new(STDERR)
		logger.level = Logger::ERROR
		
		begin
			timeout(timeout) do
				begin
					ssh_transport = Net::SSH::Transport::Session.new('localhost', {:logger => logger, :port => port})
					results[:header] = ssh_transport.server_version().header();
					results[:server_version] = ssh_transport.server_version().version();
					results[:cookie] = ssh_transport.algorithms().server_data()[:raw][1 ... 17].bytes().to_a()
					results[:kex_algorithms] = ssh_transport.algorithms().server_data()[:kex]
					results[:server_host_key_algorithms] = ssh_transport.algorithms().server_data()[:host_key]
					results[:encryption_algorithms_client_to_server] = ssh_transport.algorithms().server_data()[:encryption_client]
					results[:encryption_algorithms_server_to_client] = ssh_transport.algorithms().server_data()[:encryption_server]
					results[:mac_algorithms_client_to_server] = ssh_transport.algorithms().server_data()[:hmac_client]
					results[:mac_algorithms_server_to_client] = ssh_transport.algorithms().server_data()[:hmac_server]
					results[:compression_algorithms_client_to_server] = ssh_transport.algorithms().server_data()[:compression_client]
					results[:compression_algorithms_server_to_client] = ssh_transport.algorithms().server_data()[:compression_server]
					results[:languages_client_to_server] = ssh_transport.algorithms().server_data()[:language_client]
					results[:languages_server_to_client] = ssh_transport.algorithms().server_data()[:language_server]
					
					results[:server_keys] = []
					results[:server_keys] << read_key(ssh_transport.algorithms().key_data()[:server_key])
					
					ssh_transport.algorithms().algorithms()[:host_key].reject {|x| x == ssh_transport.algorithms().key_data()[:type]}.each do|host_key_algorithm|
						ssh_transport.close()
						ssh_transport = Net::SSH::Transport::Session.new('localhost', {:logger => logger, :host_key => host_key_algorithm, :paranoid => false})
						
						results[:server_keys] << read_key(ssh_transport.algorithms().key_data()[:server_key])
					end
					
					ssh_authentication = Net::SSH::Authentication::Session.new(ssh_transport, {:logger => logger, :auth_methods => ["none"]})
					ssh_authentication.authenticate("ssh-connection", "dummy")
					
					results[:authentication_methods] = ssh_authentication.allowed_auth_methods()
				rescue Net::SSH::AuthenticationFailed => ex
				end
			end
		rescue Timeout::Error => err	
			return {:host => host, :port => port, :timestamp => Time.now(), :status => :ERROR, :type => :TIMEOUT, :error => err}
		rescue Errno::ECONNREFUSED => err
			return {:host => host, :port => port, :timestamp => Time.now(), :status => :ERROR, :type => :CONNECTION_REFUSED, :error => err}
		end

		return results
	end
end
