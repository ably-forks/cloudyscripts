require 'parser/command/abstract_command_result'
require 'parser/command/abstract_command'
require 'parser/parse_exception'
require 'parser/result_type'

class AttachFileCommandResult < AbstractCommandResult
  attr_reader :file

  def initialize(check, severity, message, file)
    super(check, severity, message, ResultType::FILE)
    @file = file
  end

  def to_string()
    if @message then
      return "#{@message}: #{@file}"
    else
      return "See attached file #{@file}"
    end
  end

  def to_hash()
    return super.to_hash().merge({:file => file})
  end
end

# A command that uploads a file from the audited host.
class AttachFileCommand < AbstractCommand
	# Command name in the script.
	COMMAND = "ATTACH_FILE"
	
	@@log = Logger.new(STDOUT)
	
	
	attr_reader :severity
	attr_reader :check
	attr_reader :remote_path
	attr_reader :message
	
	def initialize(check, severity, args)
		message = args[1 .. -1].join if args.length >= 2
		super(check, severity, message)
		
		@@log.level = Logger::DEBUG
		
		@remote_path = args[0].strip if args.length >= 1 or raise ParseException.new("#{COMMAND} did not supply the file argument")
		@local_path = nil
	end
		
	def process(parser)
		if parser.attachment_dir then
			filename = (/^(\/?([^\/]+\/)*)([^\/]+)$/.match(@remote_path) or {3 => nil})[3]
			@local_path = parser.attachment_dir + "/" + filename 
			parser.connection.copy_from_remote(@remote_path, @local_path)
		else
			@@log.info { "file #{@remote_path} attached, but no attachment dir specified" }
		end
	end

  def result()
    return AttachFileCommandResult.new(@check, @severity, @message, @local_path)
  end
end