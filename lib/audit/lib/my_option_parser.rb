require 'optparse'

class MyOptionParser
	
	attr_reader :options
	
	def initialize(args)
		@args = args
	end
	
	def parse()
		@options = {}
		
		opts = OptionParser.new do|opts|
			#Banner string displayed at top of help
			opts.banner = "Usage: ./main.rb\t--ssh HOST[:PORT] [--user USERNAME] --key KEYFILE --benchmark BENCHMARK"
			opts.separator "\t\t\t--ami AMI-ID --credentials CREDENTIALS --benchmark BENCHMARK"
	
	
			@options[:verbose] = false
			opts.on('-v', '--[no-]verbose', 'Output more information') do|v|
				@options[:verbose] = v
			end
	                
			opts.on('-A', '--ami AMI-ID', String, 'Select this AMI for audit') do|ami|
				@options[:ami] = ami
			end
			
			opts.on('-S', '--ssh HOST', String, 'Select this host for audit') do|host|
				@options[:ssh] = host
			end
			
			opts.on('-B', '--benchmark BENCHMARK', String, 'Use this benchmark file') do|bm|
				@options[:benchmark] = bm
			end
			
			opts.on('-K', '--key KEY', String, 'Use this private key file for authentication') do|key|
				@options[:key] = key
			end
			
			opts.on('-P', '--password PASSWORD', String, 'Use this password for authentication') do|pwd|
				@options[:password] = pwd
			end
			
			opts.on('-C', '--credentials CREDENTIALS', String, 'Use these Amazon Account credentials to start the AMI') do|cd|
				@options[:credentials] = cd
			end
	                
			opts.on_tail("-h", "--help", "Show this message") do
				puts opts
				exit
			end
		end
	
		opts.parse(@args)
		
		if @options[:ssh].nil? and @options[:ami].nil? then
			print "You must specify one of the --ssh or --ami options. Exiting.\n"
			exit 1
		end
		
		if not @options[:ssh].nil? and not @options[:ami].nil? then
			print "Options --ssh and --ami are mutually exclusive, but both chosen. Please specify only one of them. Exiting.\n"
			exit 1
		end
		
		if @options[:benchmark].nil? then
			print "Option --benchmark is required. Please specify a benchmark file for this audit. Exiting.\n"
			exit 1
		end
		
		if not @options[:ssh].nil? and @options[:key].nil? and @options[:password].nil? then
			print "At least one authentication method for SSH is required. Please specify either --key or --password. Exiting.\n"
			exit 1
		end
		
		return self
	end
	
	def connection_type
		return :ami unless @options[:ami].nil?
		return :ssh unless @options[:ssh].nil?
		return :none
	end
	
	def ssh_credentials
		raise "SSH credentials requested although SSH connection method is not chosen" if @options[:ssh].nil?
		raise "No SSH authentication method chosen" if @options[:password].nil? and @options[:key].nil?
		
		cred = {:host => @options[:ssh]}
		if @options[:user].nil? then
			cred[:user] = 'root' 
		else 
			cred[:user] = @options[:user]
		end
		cred[:key_data] = @options[:key] unless @options[:key].nil?
		cred[:password] = @options[:password] unless @options[:password].nil?
		
		return cred
	end
	
	def benchmark
		raise "No benchmark file specified" if @options[:benchmark].nil?
		return @options[:benchmark]
	end
end  