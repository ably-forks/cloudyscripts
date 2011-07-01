require 'parser/command/abstract_command'
require 'parser/command/abstract_command_result'
require 'parser/result_type'
require 'parser/parse_exception'

class DataCommandResult < AbstractCommandResult
  attr_reader :key
  attr_reader :value

  def initialize(check, severity, key, value)
    super(check, severity, "custom check data", ResultType::DATA)
    @key = key
	 @value = value
  end

  def to_string()
    return "[" + @key + "] = " + @value
  end

  def to_hash()
    return super.to_hash().merge({:key => @key, :value => @value})
  end

  def visible?
    return true
  end
end

class DataCommand < AbstractCommand
	COMMAND = "DATA"

	def initialize(check, severity, args)
		@data = args

	 @key = args[0] if args.length >= 1 or raise ParseException, "#{COMMAND} did not supply the data key argument: '#{args}'"
	 @value = args[1] if args.length >= 2 or raise ParseException, "#{COMMAND} did not supply the data value argument: '#{args}'"
    super(check, severity, "custom check data")
	end

  def result()
    return DataCommandResult.new(@check, @severity, @key, @value)
  end
end