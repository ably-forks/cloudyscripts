require 'connection/ssh_connection'


class ConnectionFactory
	def initialize(options)
		if options[:logger] then
			@logger = options[:logger]
		else
			@logger = Logger.new(STDOUT)
		end
	end
	
	def create(options)
		raise "Need option :connection_type" unless options[:connection_type]
		raise "Need option :connection_params" unless options[:connection_params] 

		case options[:connection_type]
			when :ssh
				return SshConnection.new({:connection_params => options[:connection_params], :logger => @logger})
			when :ami
				return AmiConnection.new({:connection_params => options[:connection_params], :logger => @logger})
			else
				raise "Unknown connection type"
		end
	end
end
				