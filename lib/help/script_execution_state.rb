require "help/state_transition_helper"

# Implements a little state-machine.
# Usage: for every state you need, extend this class.
# The method enter() must be implemented for every state you code and
# return another state.
class ScriptExecutionState
  include StateTransitionHelper
  
  # context information for the state (hash)
  attr_reader :context, :logger

  def initialize(context)
    @context = context
    @state_change_listeners = []
    @logger = context[:logger]
    if @logger == nil
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::WARN
    end
  end

  # Listener should extend #StateChangeListener (or implement a 
  # state_changed(state) method). Note: calls are synchronous.
  def register_state_change_listener(listener)
    @state_change_listeners << listener
  end

  # Start the state machine using this state as initial state.
  def start_state_machine
    @current_state = self
    @logger.info "start state machine with #{@current_state.to_s}"
    while !@current_state.done? && !@current_state.failed?
      begin
        @logger.info "state machine: current state = #{@current_state.to_s}"
        @current_state = @current_state.enter()
        notify_state_change_listeners(@current_state)
      rescue Exception => e
        if @context[:result] != nil
          @context[:result][:details] = e.backtrace().join("\n")
        end
        @current_state = FailedState.new(@context, e.to_s, @current_state)
        notify_state_change_listeners(@current_state)
        @logger.warn "StateMachine exception during execution: #{e}"
        @logger.warn "#{e.backtrace.join("\n")}"
      end
    end
    @current_state
  end

  # Returns the state that is reached after execution.
  def end_state
    @current_state
  end

  # To be implemented. Executes the code for this state.
  def enter
    raise Exception.new("TaskExecutionState is abstract")
  end

  # To be implemented. Indicates if the final state is reached.
  def done?
    false
  end

  # To be implemented. Indicates if the final state is a failure state.
  def failed?
    false
  end

  def to_s
    s = self.class.to_s
    s.sub(/.*\:\:/,'')
  end

  private

  # Notifies all listeners of state changes
  def notify_state_change_listeners(state)
    @state_change_listeners.each() {|listener|
      listener.state_changed(state)
    }
  end

end

# Standard state reached when an exception occurs.
class FailedState < ScriptExecutionState
  attr_accessor :failure_reason, :from_state
  def initialize(context, failure_reason, from_state)
    super(context)
    @failure_reason = failure_reason
    @from_state = from_state
  end
  def done?
    true
  end
  def failed?
    true
  end
end

# Done.
class Done < ScriptExecutionState
  def done?
    true
  end
end
