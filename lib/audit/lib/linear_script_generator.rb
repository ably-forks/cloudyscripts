require 'benchmark'

class LinearScriptGenerator
	
	def self.generate(benchmark)
		retval = ""
		resolved_dependencies = benchmark.execution_order

		script_header = benchmark.element("script_header.template")
		header = benchmark.element("header.template")
		footer = benchmark.element("footer.template")
		
		raise ItemNotFoundException.new("header.template"), "header template missing in benchmark" if header.nil?
		raise ItemNotFoundException.new("footer.template"), "footer template missing in benchmark" if footer.nil?
		raise ItemNotFoundException.new("script_header.template"), "script header template missing in benchmark" if script_header.nil?
	
		retval = script_header if script_header

		resolved_dependencies.flatten.each do|x|
			depends_condition = ""
	   		x.dependencies.each do|y|
				depends_condition = depends_condition + "-a ${" + y.id + "_EXITCODE} -eq 0 "
			end
	
			retval = retval + "\n" + header.gsub(/%%SCRIPT_ID%%/, x.id).gsub(/%%DEPENDS_CONDITION%%/, depends_condition) + "\n"
			retval = retval + (x.script)
			retval = retval + "\n" + footer.gsub(/%%SCRIPT_ID%%/, x.id)
		end
		return retval
	end
end
