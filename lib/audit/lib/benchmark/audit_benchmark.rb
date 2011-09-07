require 'audit/lib/benchmark/check'
require 'audit/lib/benchmark/item_exception'
require 'audit/lib/lazy'


class AuditBenchmark
	attr_reader :item_repository
	
	def execution_order()
		# resolve dependencies between checks based on the depends-tag of the checks.
		# In a first pass, all dependencies are discovered iteratively popping checks
		# from a queue of checks with unresolved dependencies, pushing them onto a resolved
		# queue and pushing the check's dependencies onto the unresolved queue if they
		# are not yet in the resolved or unresolved queue. Also, the reversed dependencies
		# (which check is needed by which) are stored for the second pass.
		#
		# In a second pass, starting from checks which do not depend on any other checks,
		# all checks are labelled with the dependency level they're in. Checks without dependencies
		# have dependency level 0, checks which rely on checks from level 0 have level 1,
		# and so on. This is not the optimal solution for the problem ... but I have forgot why,
		# so figure this out yourself.
		#
		# You might wonder why I don't do dependency tracking with the Imports and Exports
		# declarations: If there are two scripts which provide a variable (alternatives),
		# it is very easy to write a mediating script, which chooses one of the provider scripts,
		# and then can be depended on, but it is very hard to do the resolution based on 
		# imports and exports. So imagine this like the linker, which uses library/object
		# names to include dependencies, but still checks that all symbols are resolved
		# correctly (TODO: Add a check that all Imports are satisfied by Exports)
		
		#find all dependencies
		items = @children.dup
		
		unresolved = []
		while not items.empty?
			item = items.shift
			if item.class == Group
				item.children.each do|x| 
					items << x unless items.include? x or unresolved.include? x
				end
			elsif item.class == Check
				unresolved << item
			end
		end

		resolved = []
		dependency_root = []
		reversed_dependencies = {}
		iterations = 0
		
		while !unresolved.empty? and iterations < @item_repository.length
			cur = unresolved.shift
			
			dependency_root.push(cur) if cur.dependencies.empty? and not dependency_root.include? cur
			
			cur.dependencies.each do|dep|
				unresolved.push dep unless unresolved.include? dep or resolved.include? dep
				reversed_dependencies[dep] = [] if reversed_dependencies[dep].nil?
				reversed_dependencies[dep] << cur
			end
		end
		
		untagged = []
		tagged = []
		
		dependency_root.each {|x| untagged.push(x)}
		untagged.push(:NEXT_LEVEL)
		
		level = 0
		while untagged.length > 1
			cur = untagged.shift
			
			if cur == :NEXT_LEVEL then
				level = level + 1
				untagged.push(:NEXT_LEVEL)
				next
			end
			
			tag = tagged.select {|x| x[:check] == cur}
			if tag.empty? then
				tagged << {:level => level, :check => cur}  
			else 
				raise "multiple tags for check #{cur.id} found" if tag.length != 1
				
				tag[0][:level] = level
			end
			
			unless reversed_dependencies[cur].nil? then
				reversed_dependencies[cur].each {|x| untagged.push(x)}
			end
		end
		
		retval = []
		(0 .. level).each {|i| retval.push(tagged.select {|x| x[:level] == i}.map {|x| x[:check]})}
		
		return retval
	end
	
	def element(name)
		@elements = {} unless @elements
		@elements[name] = element_impl(name) unless @elements[name]
		
		return @elements[name]
	end

  def rules()
    untraversed = @children.dup
    rules = []

    while untraversed.length > 0
      item = untraversed.shift

      if item.kind_of? Group then
        untraversed = untraversed + item.children
      elsif item.kind_of? Check then
        rules << item
      end
    end

    return rules.uniq
  end

  def dependencies()
    return (rules().map {|x| x.dependencies }.flatten()).uniq
  end

  def automatic_dependencies()
    return dependencies() - rules()
  end

#  def checks()
#    checks = []
#    not_traversed = @children.dup
#
#    while !not_traversed.empty? do
#      item = not_traversed.shift
#
#      if (item.class == Group) then
#        item.children.each do |child|
#          not_traversed << child unless not_traversed.include? child
#        end
#      elsif item.class == Check then
#        checks << item
#        item.dependencies.each do |dep|
#          not_traversed << dep unless not_traversed.include? dep
#        end
#      end
#    end
#
#    return checks
#  end

  def duration()
    #execution_order().flatten().each().inject(0) {|result, element| result + element.duration}
    execution_order().flatten().inject(0) {|result, element| result + element.duration}
  end

  def to_hash()
    return {
      :type => :BENCHMARK,
      :id => @id,
      :name => @name,
      :description => @description,
      :children => Lazy.new(Lazy.new(@children, :reject) {|x| !x.in_report?}, :map) {|child| Lazy.new(child, :to_hash)}
    }
  end
end
