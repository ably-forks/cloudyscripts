# Implements a little state-machine.
# Usage: for every state you need, extend this class.
# The method enter() must be implemented for every state you code and
# return another state.
class ScriptExecutionState
  # context information for the state (hash)
  attr_reader :context

  def initialize(context)
    @context = context
  end

  # Start the state machine using this state as initial state.
  def start_state_machine
    @current_state = self
    puts "start state machine with #{@current_state.inspect}"
    while !@current_state.done? && !@current_state.failed?
      begin
        @current_state = @current_state.enter()
      rescue Exception => e
        @current_state = FailedState.new(@context, e.to_s, @current_state)
        puts "Exception: #{e}"
        puts "#{e.backtrace.join("\n")}"
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

end
