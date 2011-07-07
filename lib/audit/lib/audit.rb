require 'logger'
	
require 'audit/lib/connection/connection_factory'
require 'audit/lib/benchmark/benchmark_factory'
require 'audit/lib/linear_script_generator'
require 'audit/lib/parser/script_output_parser'
require 'audit/lib/util/random_string'
require 'audit/lib/benchmark/benchmark_result'
require 'audit/lib/lazy'

class Audit
	attr_reader :benchmark
	attr_reader :connection
	attr_reader :start_time
	attr_reader :end_time
	attr_reader :results
	attr_reader :exceptions

	# Create a new audit.
	# The audit will be initialized, but not started.
	# * <em>benchmark</em> is a path string that points to the benchmark file
	#   that should be used for the audit.
	# * <em>attachment_dir</em> is a path string that points to the directory where incoming
	#   files will be saved (that directory needs to be writable). If a null value
	#   is passed, ATTACH_FILE requests will be ignored and no files will be saved.
	# * <em>connection_type</em> is a symbol for the connection type that will be used.
	#   Anything that can be given to the ConnectionFactory (connection/ConnectionFactory::create)
	#   is valid (:ssh, ...)
	# * <em>connection_params</em> is a dictionary of connection parameters that are
	#   specific to the connection type chosen with <em>connection_type</em>. See the
	#   ConnectionFactory class for more datails.
	# * <em>logger</em> is an optional logger that the debug output is logged to
	def initialize(options)
		raise "Option :benchmark is required" unless options[:benchmark]
#		raise "Option :attachment_dir is required" unless options[:attachment_dir]
		raise "Option :connection_type is required" unless options[:connection_type]
		raise "Option :connection_params is required" unless options[:connection_params]

		if options[:logger] then
			@logger = options[:logger]
		else
			@logger = Logger.new(STDOUT)
		end
		
		@benchmark = BenchmarkFactory.new(:logger => @logger).load(:benchmark => options[:benchmark])
		@connection = ConnectionFactory.new(:logger => @logger).create(:connection_type => options[:connection_type], 
		                                                               :connection_params => options[:connection_params])
		@results = {}
		@exceptions = []
		@attachment_dir = options[:attachment_dir]
	end
	
	def start(parallel = true)
		@start_time = Time.now.utc
	
		launch_audit = Proc.new do
			remote_script_path = "/tmp/" + RandomString::generate() + ".sh"
			script = LinearScriptGenerator.generate(@benchmark)

			@connection.open() do|conn|
				conn.write_to_remote_file(script, remote_script_path)
				@response_parser = ScriptOutputParser.new(:benchmark => @benchmark, 
				                                          :connection => conn, 
				                                          :attachment_dir => @attachment_dir, 
				                                          :logger => @logger)
				@response_parser.on_check_completed() do|rule_result|
					@results[rule_result.rule_idref] = rule_result
					@check_completed_handler.call(rule_result) unless @check_completed_handler.nil?
				end
				@response_parser.on_finished() do|benchmark, rule_results|
					@end_time = Time.now.utc
					@finished_handler.call(benchmark, rule_results) unless @finished_handler.nil?
				end
					
				conn.exec("/bin/sh " + remote_script_path)
			end
		end
	
		if (parallel) then
			begin
				Thread.new {launch_audit.call}
			rescue Exception => ex
				exceptions << ex
				@logger.error {"Exception type: #{ex.class.name}"}
				@logger.error {"=== stack trace of exception #{ex.message}"}
				ex.backtrace.each do|line|
					@logger.error {line}
				end
				@logger.error {"=== end stack trace"}
			end
		else
			launch_audit.call
		end
		return self
	end

	def on_check_completed(&block)
		@check_completed_handler = block
	end

	def on_finished(&block)
		@finished_handler = block
	end

	def progress()
		return ((@response_parser.progress() unless @response_parser.nil?) or 0.0)
	end
	
	def abort()
		@connection.abort() if @connection
	end
	
	def finished?()
		return !end_time.nil?
	end

	def name()
		return (@benchmark.name || @benchmark.id)  + "#" + @connection.to_s() + (@start_time ? "#" + @start_time.to_s() : "")
	end
	
	def remaining_time()
		return @benchmark.duration() if @response_parser.nil?
		return @response_parser.remaining_time()
	end

	def to_hash()
		return {
			:type => :AUDIT,
			:start_time => @start_time,
			:end_time => @end_time,
			:connection => @connection.to_hash(),
			:benchmark => @benchmark.to_hash(),
			:results => Lazy.new(@results.values(), :map) {|x| Lazy.new(x, :to_hash)}
		}
	end
end
