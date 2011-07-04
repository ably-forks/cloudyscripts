# The superclass for all response commands from scripts
# each subclass must have a constant named COMMAND, which is the string
# version of the command as sent by the worker script
class AbstractCommand
	# The check that issued this command.
  attr_reader :check
	# The severity of this command.
  attr_reader :severity
	# The message associated with this command.
  attr_reader :message
  
	# Create a new AbstractCommand. 
	# Should only be called from subclasses, as this class is abstract,
	# * <em>check</em>
	# * <em>severity</em>
	# * <em>message</em>
  def initialize(check, severity, message)
    @check = check
    @severity = severity
    @message = message
  end

  # Abstract method to be implemented by subclasses.
  # Perform any action neccessary to obtain results, like copying a file to the local host.
  def process(parser)
  end

  # Abstract method to be implemented by subclasses.
  # return a result object, contained in an instance of kind AbstractCommandResult
  def result()
  end
end
