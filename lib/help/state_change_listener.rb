# Defines a template for a class that allows to be notified
# on state-changes in #ScriptExecutionState. A listener must be
# registered via #ScriptExecutionState::register_state_change_listener.
# When a state changes the method #state_changed is called.

class StateChangeListener
  # Method called when a state changes. Note: calls are synchronous, the
  # listener should return quickly and handle more complicated routines
  # in a different thread.
  def state_changed(state)
    raise Exception.new("StateChangeListener: state change notification not implemented")
  end
end
