require 'lazy'

class Check
	attr_reader :id 				# The ID by which this check is referenced from other elements
	attr_reader :name 			# A human-readable name for this check
	attr_reader :description 	# A short description of the goals of this check
	attr_reader :script 			# The actual sh script that will be executed to gather values
	attr_reader :dependencies 	# An array if ID string, which contain references to required Check (not Group!) 
										# objects that must be executed before this check 
	attr_reader :duration		# duration of this check in seconds; per default, one second is assumed
	
	def initialize(id, script, name = nil, dependencies = [], description = nil, duration = 1)
		@id = id
		@name = name
		@dependencies = dependencies || []
		@description = description
		@script = script
		@duration = (duration or 1)
	end

  def to_hash()
    return {
      :type => :CHECK,
      :id => @id,
      :name => @name,
      :dependencies => Lazy.new(@dependencies, :map) {|check| check.id},
      :description => @description
    }
  end

  def in_report?()
    return true
  end
end