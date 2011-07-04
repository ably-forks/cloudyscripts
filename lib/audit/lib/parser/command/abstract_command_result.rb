# To change this template, choose Tools | Templates
# and open the template in the editor.
class AbstractCommandResult
  attr_reader :check
  attr_reader :severity
  attr_reader :message
  attr_reader :type
  
  def initialize(check, severity, message, type)
    @check = check
    @severity = severity
    @message = message
    @type = type
  end
  
  def to_string()
    return @message
  end

  def to_hash()
    return {:rule => @check.id,
            :severity => @severity,
            :message => @message,
            :type => @type}
  end

  def visible?
    return true
  end
end
