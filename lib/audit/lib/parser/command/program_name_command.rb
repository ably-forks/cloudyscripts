require 'audit/lib/parser/command/abstract_command'
require 'audit/lib/parser/command/abstract_command_result'
require 'audit/lib/parser/result_type'

class ProgramNameCommandResult < AbstractCommandResult
  attr_reader :program_name
  attr_reader :program_version
  
  def initialize(check, severity, message, name, version)
    super(check, severity, message || "program found", ResultType::PROGRAM_NAME)
    @program_name = name
    @program_version = version
  end

  def to_string()
    if @message then
      return "#{@message}: #{@program_name} #{@program_version}"
    else
      return "#{@program_name} #{@program_version}"
    end
  end

  def to_hash()
    return super.to_hash().merge({:program_name => @program_name, :program_version => @program_version})
  end
end

class ProgramNameCommand < AbstractCommand
	COMMAND="PROGRAM_NAME"
	
	def initialize(check, severity, args)
		@name = args[0].strip if args.length >= 1 or raise ParseException "#{COMMAND} did not supply the program name argument: '#{text}'"
		@version = args[1].strip if args.length >= 2
		message = (args.length >= 3 ? args[2 .. -1].join : nil)

    super(check, severity, message)
	end

  def result()
    return ProgramNameCommandResult.new(@check, @severity, @message, @name, @version)
  end
end
