require "help/state_change_listener"

class MockedStateChangeListener < StateChangeListener

  def state_changed(state)
    puts "state change notification: new state = #{state.to_s} #{state.done? ? '(terminated)' : ''}"
  end

  def new_message(message, level = Logger::DEBUG)
    puts "###{level}### new progress message = #{message}"
  end

end
