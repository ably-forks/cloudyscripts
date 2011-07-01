require 'lazy'


class Group
	attr_reader :id # The unique ID by which this group is referenced from other elements
	attr_reader :name # A human-readable name for this group
	attr_reader :description # A descriptive string for this group
	attr_accessor :children # Allowed children are Check and Group objects
	
	def initialize(id, name = nil, description = nil)
		@id = id
		@name = name
		@description = description
		@children = []
	end

  def to_hash()
    return {
      :type => :GROUP,
      :id => @id,
      :name => @name,
      :description => @description,
      :children => Lazy.new(Lazy.new(@children, :reject) {|x| !x.in_report?}, :map) {|child| Lazy.new(child, :to_hash)}
    }
  end

  def in_report?()
    true
  end
end