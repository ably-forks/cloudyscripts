# To change this template, choose Tools | Templates
# and open the template in the editor.

require 'parser/command/abstract_command'
require 'parser/command/abstract_command_result'


class ListeningPortCommandResult < AbstractCommandResult
  attr_reader :port
  attr_reader :process
  attr_reader :interface

  def initialize(check, severity, message, port, interface, process)
    super(check, severity, message || "found open port", ResultType::LISTENING_PORT)
    @port = port
    @process = process
    @interface = interface
  end

  def to_string()
    return "#{@message}: #{@port} on interface #{@interface} of process #{@process}"
  end

  def to_hash()
    return super.to_hash().merge({:port => @port,
        :process => @process,
        :interface => @interface})
  end
end

class ListeningPortCommand < AbstractCommand
  COMMAND = "OPEN_PORT"

	def initialize(check, severity, args)
    @port = args[0].to_i if (args.length >= 1 and /^[0-9]+$/.match(args[0])) or raise ParseException "#{COMMAND} did not supply the port argument: '#{text}'"
    @process = (args[1] if args.length >= 2) || ""
    @interface = (args[2] if args.length >= 3) || ""
		message = args[3 .. -1].join if args.length >= 4

    super(check, severity, message)
	end

  def result()
    return  ListeningPortCommandResult.new(@check, @severity, @message, @port, @interface, @process)
  end
end
