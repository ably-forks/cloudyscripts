require 'audit/lib/parser/command/abstract_command'
require 'audit/lib/parser/command/abstract_command_result'
require 'audit/lib/parser/result_type'

class CpeNameCommandResult < AbstractCommandResult
  def initialize(check, severity, message, cpe_name)
    super(check, severity, message || "found program", ResultType::CPE_NAME)
    @cpe_name = cpe_name
  end

  def get_cpe_name()
    return @cpe_name
  end

  def to_string()
    return "#{@message}: #{@cpe_name}"
  end

  def to_hash()
    return super.to_hash().merge({:cpe_name => @cpe_name})
  end
end

class CpeNameCommand < AbstractCommand
	COMMAND = "CPE_NAME"
	
	def initialize(check, severity, args)
		@cpe_name = args[0] if args.length >= 1 or raise ParseException "#{COMMAND} did not supply the cpe name argument: '#{text}'"
		message = args[2 .. -1].join if args.length >= 2

    super(check, severity, message)
	end

  def result()
    return CpeNameCommandResult.new(@check, @severity, @message, @cpe_name)
  end
end
