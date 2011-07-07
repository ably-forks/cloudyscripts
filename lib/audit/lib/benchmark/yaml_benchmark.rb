require 'yaml'
require 'logger'
require 'zip/zip'

require 'audit/lib/benchmark/group'
require 'audit/lib/benchmark/item_exception'
require 'audit/lib/benchmark/check'
require 'audit/lib/benchmark/audit_benchmark'
require 'audit/lib/benchmark/automatic_dependencies'


class YamlBenchmark < AuditBenchmark
	CHECK_FILE_EXTENSION=".check"
	GROUP_FILE_EXTENSION=".group"
	GROUP_ID="ID"
	GROUP_NAME="Name"
	GROUP_DESCRIPTION="Description"
	GROUP_CHILDREN="Children"
	CHECK_ID="ID"
	CHECK_SCRIPT="Script"
	CHECK_NAME="Name"
	CHECK_DEPENDENCIES="Depends"
	CHECK_DESCRIPTION="Description"
  CHECK_DURATION="Duration"
	BENCHMARK_ID="BENCHMARK"
	
	attr_reader :id
	attr_reader :name
	attr_reader :description
	attr_reader :children
	
	def initialize(options)
		raise "Need option :benchmark" unless options[:benchmark]
		
		if options[:logger]
			@logger = options[:logger]
		else
			@logger = Logger.new(STDOUT)
		end
		
		if !File.exist?(options[:benchmark]) then
			@logger.error("Specified benchmark file '#{options[:benchmark]}' does not exist") 
			raise "Specified benchmark file '#{options[:benchmark]}' does not exist"
		end
		
		@logger.info("Loading benchmark '#{options[:benchmark]}'")
		
		@item_repository = {}
		@benchmark_file = options[:benchmark]
		group_hashes = []
		check_hashes = []
		Zip::ZipFile.open(@benchmark_file, Zip::ZipFile::CREATE) do|zipfile|
			zipfile.each do|file|
				if file.name =~ /\.group$/ then
					@logger.debug {"Loading group '#{file.name}'"}
					
					hash = YAML::load( file.get_input_stream )
					raise "The group file '#{group_file}' does not contain the group's ID" unless hash[GROUP_ID]
					raise "The group file '#{group_file}' does not contain any children" unless hash[GROUP_CHILDREN]	

					@item_repository[hash[CHECK_ID]] = Group.new(hash[GROUP_ID], 
				                                             hash[GROUP_NAME], 
				                                             hash[GROUP_DESCRIPTION])
					group_hashes << hash # keep group hash for later, because we still need to add children to the group
				elsif file.name =~ /\.check$/ then
					@logger.debug {"Loading check '#{file.name}'"}
				
					hash = YAML::load( file.get_input_stream )
					raise "The check file '#{file.name}' does not contain the check's ID" unless hash[CHECK_ID]
					raise "The check file '#{file.name}' does not contain a check script" unless hash[CHECK_SCRIPT]

					@item_repository[hash[CHECK_ID]] = Check.new(hash[CHECK_ID], 
				                                             hash[CHECK_SCRIPT], 
				                                             hash[CHECK_NAME], 
				                                             [], 
				                                             hash[CHECK_DESCRIPTION],
                                                     hash[CHECK_DURATION])
					check_hashes << hash
				else
					@logger.info {"Ignoring unknown file '#{file.name}' in benchmark '#{@benchmark_file}'"}
					# unknown file, ignore
				end
			end
		end
		
		group_hashes.each do|group_hash|
			group = @item_repository[group_hash[GROUP_ID]]
			group_hash[GROUP_CHILDREN]. each do|child|
				raise ItemNotFoundException.new(child), "Item '#{child}' from group '#{group.id}' not found" unless @item_repository[child]
				item = @item_repository[child]
				raise BadItemClassErooxception, "Item '#{child}' from group '#{group.id}' has wrong item class '#{item.class.name}'" unless item.class == Check || item.class == Group
				
				group.children << item
			end
		end
		
		# set dependencies
		check_hashes.each do|check_hash|
			check = @item_repository[check_hash[CHECK_ID]]
			if check_hash[CHECK_DEPENDENCIES] then
				check_hash[CHECK_DEPENDENCIES].each do|dep|
					raise ItemNotFoundException.new(dep), "Item '#{dep}' which is depended on by check '#{check.id}' not found" unless @item_repository[dep]
					check.dependencies << @item_repository[dep]
				end
			end
		end
		
		benchmark = @item_repository[BENCHMARK_ID] or raise ItemNotFoundException.new("benchmark.group"), "Benchmark file benchmark.group not found in benchmark zipfile '#{benchmark_file}'"
		raise BadItemClassException, "Benchmark has wrong item class #{benchmark.class.name}, expected is Group" unless benchmark.class == Group
		@item_repository.delete(BENCHMARK_ID) #The benchmark group is not really an item, so remove it from the item set

		@id = benchmark.id
		@name = benchmark.name
		@description = benchmark.description
    @children = benchmark.children
    auto_deps = AutomaticDependencies.new(automatic_dependencies())
    @item_repository[auto_deps.id] = auto_deps
		@children = [auto_deps] + benchmark.children

	end
	
	#get a raw benchmark element by name. This is used by other classes like script generators
	#to retrieve information from the benchmark that was stored there for them.
	def element_impl(name)
		return Zip::ZipFile.open(@benchmark_file, Zip::ZipFile::CREATE) {|zipfile| zipfile.read(name)}
	end

  def get_item(id)
    raise ItemNotFoundException.new(id), "Item #{id} not found" if @item_repository[id].nil?
    return @item_repository[id]
  end
end
