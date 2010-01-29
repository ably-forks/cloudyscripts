# Defines a template for a class that allows to be notified
# about messages during script execution.A listener must be
# registered via #Ec2Script::register_state_change_listener.
# New messages are passed via the method #new_message.

class ProgressMessageListener
  # Method called when a state changes. Note: calls are synchronous, the
  # listener should return quickly and handle more complicated routines
  # in a different thread. The level corresponds to the logger.LEVEL and
  # allows to signal the importance of a message
  def new_message(message, level = Logger::INFO)
    raise Exception.new("ProgressMessageListener: new message notification not implemented")
  end
end
