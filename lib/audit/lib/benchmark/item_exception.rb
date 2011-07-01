class ItemException < Exception
end

class ItemNotFoundException < ItemException
  attr_reader :missing_item
  
  def initialize(missing_item)
    @missing_item = missing_item
  end
end

class BadItemClassException < ItemException
end