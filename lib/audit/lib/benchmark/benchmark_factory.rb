require 'audit/lib/benchmark/yaml_benchmark'

class BenchmarkFactory
	def initialize(options)
		if options[:logger] then
			@logger = options[:logger]
		else
			@logger = Logger.new(STDOUT)
		end
	end

	def load(options)
		raise "Need option :benchmark" unless options[:benchmark]
		
		if options[:benchmark] =~ /\.xml$/ then
			return XccdfBenchmark.new({:benchmark => options[:benchmark], :logger => @logger})
		elsif options[:benchmark] =~ /\.zip$/ then
			return YamlBenchmark.new({:benchmark => options[:benchmark], :logger => @logger})
		else
			raise "Unknown benchmark type"
		end
	end
end
