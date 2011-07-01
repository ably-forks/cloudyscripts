require 'parser/command/abstract_command'
require 'parser/command/abstract_command_result'
require 'parser/result_type'

class MessageCommandResult < AbstractCommandResult
  def initialize(check, severity, message)
    super(check, severity, message, ResultType::MESSAGE)
  end
end

class MessageCommand < AbstractCommand
	COMMAND = "MESSAGE"
	
	def initialize(check, severity, args)
    super(check, severity, args[0 .. -1].join)
	end

  def result()
    return MessageCommandResult.new(@check, @severity, @message)
  end
end