# To change this template, choose Tools | Templates
# and open the template in the editor.
require 'parser/command/abstract_command_result'
require 'parser/command/abstract_command'
require 'parser/result_type'

class CheckFinishedCommandResult < AbstractCommandResult
  attr_reader :exit_code

  def initialize(check, severity, message, exit_code)
    super(check, severity, message, ResultType::CHECK_FINISHED)
    @exit_code = exit_code
  end

  def to_string()
    if message then
      return "Check #{@check.id} finished: #{@message}"
    else
      return "Check #{@check.id} has finished"
    end
  end

  def to_hash()
    return super.to_hash().merge({:exit_code => @exit_code})
  end

  def visible?
    return false
  end
end

class CheckFinishedCommand < AbstractCommand
  COMMAND = "CHECK_FINISHED"

	def initialize(check, severity, args)
    @exit_code = args[0] if args.length >= 1 or raise ParseException, "#{check.id} #{COMMAND} did not supply the exit code argument"
		message = args[1 .. -1].join if args.length >= 2

    super(check, severity, message)
	end

  def result()
    return CheckFinishedCommandResult.new(@check, @severity, @message, @exit_code)
  end
end
