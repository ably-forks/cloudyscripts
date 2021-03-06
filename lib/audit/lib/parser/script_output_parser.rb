require 'logger'

require 'audit/lib/parser/command/program_name_command'
require 'audit/lib/parser/command/cpe_name_command'
require 'audit/lib/parser/command/attach_file_command'
require 'audit/lib/parser/command/message_command'
require 'audit/lib/parser/command/check_finished_command'
require 'audit/lib/parser/command/listening_port_command'
require 'audit/lib/parser/command/data_command'
require 'audit/lib/parser/parse_exception'
require 'audit/lib/benchmark/rule_severity'
require 'audit/lib/parser/stdout_line_buffer'
require 'audit/lib/benchmark/rule_result'

# This class parses the output generated by a sh script.
# Each output line is expected to start with the marker LINE_START
# and fields are also separated with SEPARATOR.
# 1. The first field is expected to be the name of the script part
#    that generated the message.
# 2. The second field is expected to be a severity level defined
#    in RuleSeverity (RuleSeverity).
# 3. The third field is the message type. Currently there are 
#    message types defined for program names (ProgramNameCommand),
#    file attachment (AttachFileCommand), end of a check
#    (CheckFinishedCommand), and key-value style data (DataCommand).
# 
# Author:: Jonas Zaddach, SecludIT (zaddach [at] eurecom [dot] fr)
class ScriptOutputParser
	# marker used to identify beginning of a parseable line
	LINE_START = "%%"
	# marker used to separate fields in the line
	SEPARATOR = "%%"
	
	#Logger.
	@@log = Logger.new(STDOUT)
	# Mapping of command names to commands.
	# TODO: This should be moved into a factory class
	@@command_mapper = {
		AttachFileCommand::COMMAND => AttachFileCommand,
		MessageCommand::COMMAND => MessageCommand,
		ProgramNameCommand::COMMAND => ProgramNameCommand,
		CpeNameCommand::COMMAND => CpeNameCommand,
		CheckFinishedCommand::COMMAND => CheckFinishedCommand,
		ListeningPortCommand::COMMAND => ListeningPortCommand,
		DataCommand::COMMAND => DataCommand}
	
	# connection that is used to connect to the remote host
	attr_reader :connection
	# benchmark that is run on the remote host
	attr_reader :benchmark
	# Results of the benchmark.
	# The results of each check are pushed into this array after the
	# check has completed.
	attr_reader :check_results
	# Path string of the directory where attachments are stored.
	attr_reader :attachment_dir

	# Create a new script output parser and set up the connection object
	# that output is forwarded to this parser.
	# * <em>benchmark</em> Benchmark that generates the output to parse.
	# * <em>connection</em> Connection to the remote host where the benchmark
	#   is executed.
	# * <em>attachment_dir</em> A writable directory path as string where
	#   file attachments from AttachFileCommand are supposed to be stored.
	def initialize(options)
		raise "Need parameter :benchmark" unless options[:benchmark]
		raise "Need parameter :connection" unless options[:connection]

		@connection = options[:connection]
		@benchmark = options[:benchmark]
		
		if options[:attachment_dir] then
			@attachment_dir = options[:attachment_dir][-1] == '/' ? options[:attachment_dir][0 ... -1] : options[:attachment_dir]
			if !File.exists?(@attachment_dir) || !File.writable?(@attachment_dir) then
				raise SecurityError, "attachment directory #{@attachment_dir} is not writable"
			end
		else
			@attachment_dir = nil
		end
		
		@@log.level = Logger::DEBUG
		@@log = options[:logger] if options[:logger]
		
		@check_results = {}
		@rule_results = {}

		@total_time_units = 0
		@done_time_units = 0
		@total_time_units = @benchmark.duration()

		@stdout_line_buffer = StdoutLineBuffer.new(connection)
		@stdout_line_buffer.on_line do |msg|
			consume_stdout(msg)
		end
		
		connection.on_stderr do|msg|
			consume_stderr(msg)
		end
	end	
	
  # Called whenever a new line of output was received on the connection.
  # * <em>line</em> The newly received output line.
  def consume_stdout(line)
    @@log.warn {"incomplete line '#{line}' on stdout, not terminated by \\n"} if line[-1] != "\n"
    if /^#{LINE_START}\s*([A-Za-z0-9_]+)\s*#{SEPARATOR}\s*([A-Za-z]+)\s*#{SEPARATOR}\s*([A-Za-z0-9_]+)\s*#{SEPARATOR}\s*(.*)$/.match(line) then
      #parse check id
      check = @benchmark.item_repository[$1] or process_unknown_check_id(line, $1)
      severity = RuleSeverity::parse($2)

      cmd_class = @@command_mapper[$3.upcase]

      if cmd_class.nil? then
        process_unknown_reply_command(line, check, severity, $3)
      else
        @@log.debug {"processing command #{cmd_class.name}: #{line}"}
        process_command(cmd_class.new(check, severity,  $4.split(SEPARATOR)))
      end
    else
      process_unknown_output(line)
    end
  end

  # Get the current progress of the benchmark execution as a float value between 0 and 1.
  def progress()
    return 1.0 * @done_time_units / @total_time_units
  end

  # Get the estimated remaining time in seconds.
  # This value is very inexact.
  def remaining_time()
    return @total_time_units - @done_time_units
  end
	
  # This method is called whenever data on stderr is encountered.
  # Normally this should never happen, as all scripts are supposed to suppress output
  # on stderr.
  def consume_stderr(text)
    @@log.warn {"Unexpected line on stderr: '#{text}'. Verify that scripts are not broken."}
  end

  # Called whenever a complete response line of a script has been read and the 
  #contained command was parsed successfully.
  def process_command(cmd)
    cmd.process(self)
    result = cmd.result()
    
    @@log.debug {"cmd: #{cmd.class.name}, check_id: #{cmd.check.id}"}

    (@check_results[result.check] = [result] unless
      @check_results[result.check]) or
        @check_results[result.check] << result

    process_check_finished_command(cmd) if cmd.class == CheckFinishedCommand
  end

  # Called whenever a CheckFinishedCommand was encountered.
  def process_check_finished_command(cmd)
    #calculate progress percentage
    check = cmd.result().check
    @done_time_units += check.duration

    @@log.info {"Check #{check.id} finished, progress is %.2f%" % [progress() * 100]}

    @rule_results[check.id] = RuleResult.new(check, @check_results[check])
    @check_completed_handler.call(@rule_results[check.id]) unless @check_completed_handler.nil?

    #check if benchmark is finished
    @finished_handler.call(@benchmark, @rule_results) if @finished_handler && @done_time_units == @total_time_units
  end

  # Called whenever unknown output (that does not fit the specification, i.e. does not start
  # with %%) is encountered on stdout.
  def process_unknown_output(line)
    @@log.warn {"Unexpected output line on stdout: '#{line}'. Verify that the scripts are not broken."}
  end

  # Called whenever an unknown check id was encountered.
  def process_unknown_check_id(line, check_id_string)
    raise ParseException, "Script replied with unknown check id #{$1}"
  end

  # Called whenever an unknown reply command was encountered.
  def process_unknown_reply_command(line, check, severity, cmd_string)
    @@log.warn {"Command not found: '#{line}'."}
  end

  # Set a handler that is called whenever a check has completed.
  # * <em>block</em> The given block is supposed to accept one argument, that is a RuleResult
  #   instance of the just-finished check. 
  def on_check_completed(&block)
    @check_completed_handler = block
  end

  # Set a handler that is called when the benchmark has completed.
  # * <em>block</em> The given block is supposed to accept two arguments, the first being
  #   the benchmark object, and the second an Array of RuleResult objects, one for each check
  #   completed.
  def on_finished(&block)
    @finished_handler = block
  end
end
