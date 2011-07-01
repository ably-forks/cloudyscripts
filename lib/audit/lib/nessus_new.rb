
require 'rexml/document'
require 'logger'

include REXML

class Nessus
	attr_reader :token
	
	def initialize(options = {})
		options = {:host => "127.0.0.1", :port => "8834", :timeout => "120"}.merge(options)
		
		@host = options[:host]
		@port = options[:port]
		@timeout = options[:timeout]
		
		if options[:logger] then
			@logger = options[:logger]
		else
			@logger = Logger.new(STDOUT)
		end
		
		@token = nil
	end
	
	def execute_command(command, parameters,  fail_on_error = true)
		cmd = "curl --silent --max-time #{@timeout} --insecure "
		parameters.each do|param|
			if param[:type].nil? || param[:type] == :data then
				cmd << "--data \"#{param[:value]}\" "
			elsif param[:type] == :form then
				cmd << "--form \"#{param[:value]}\" "
			elsif param[:type] == :cookie then
				cmd << "--cookie \"#{param[:value]}\" "
			else
				raise "unknown parameter type #{param[:type]}"
			end
		end
	
		cmd << "https://#{@host}:#{@port}/#{command}"
	
		@logger.info {"Executing command: #{cmd}"}
	
		result_str = `#{cmd}`
	
		raise "unexpected return value from nessus command #{command} " unless result_str.class == String
	
		result = Document.new(result_str)
		status = result.elements.inject("reply/status", []) {|r, x| r << x.text}
		
		if fail_on_error then
			raise "Invalid return status for nessus command #{command}" unless status && status.length == 1 && status[0] == "OK"
		end
		
		return result
	end

	def login(username, password)
		result = execute_command("login", [{:value => "login=#{username}"}, {:value => "password=#{password}"}])
		token = result.elements.inject("reply/contents/token", []) {|r, x| r << x.text}
		raise "Invalid token during nessus login" unless token && token.length == 1
	
		@token = token[0]
	end

	def upload_file(file)
		raise "File '#{file}' is not accessible" unless File.exist?(file) && File.readable?(file)

		reply = execute_command("file/upload", 
	   	                    [{:type => :cookie, :value => "token=#{@token}"}, 
	      	                  {:type => :form, :value => "Filedata=@#{file}"}])
		return reply.elements.inject("/reply/contents/fileUploaded", []) {|r, x| r << x.text}[0]
	end

	def import_policy(filename)
		return execute_command("file/policy/import", 
	   	                           [{:value => "file=#{filename}"},
	      	                         {:type => :cookie, :value => "token=#{@token}"}])
	end
	
	def delete_policy(id)
		return execute_command("policy/delete", 
	   	                           [{:value => "policy_id=#{id}"},
	      	                         {:type => :cookie, :value => "token=#{@token}"}])
	end

	def get_policy_ids(policy_name)
		policies = execute_command("policy/list",
	   	                               [{:type => :cookie, :value => "token=#{@token}"}])
		return policies.elements.inject("/reply/contents/policies/policy[policyName='#{policy_name}']/policyID", []) {|r, x| r << x.text}
	end
	

	def import_policy_file(file)
		policy_name = Nessus.get_policy_name_from_file(file)
		policy_ids = get_policy_ids(policy_name)
		policy_ids.each do|id|
			delete_policy(id)
		end
		uploaded_name = upload_file(file)
		policies = import_policy(uploaded_name)
		return policies.elements.inject("/reply/contents/policies/policy[policyName='#{policy_name}']/policyID", []) {|r, x| r << x.text}[0]
	end
	
	#Start a new nessus scan
	#
	# @param :policy_id The policy id of the policy to use (String)
	# @param :targets The scan targets (String or Array of String)
	def start_scan(options)
		raise "Missing parameter :policy_id" unless options[:policy_id]
		raise "Missing parameter :targets" unless options[:targets]
		
		scan_opts = [{:value => "policy_id=#{options[:policy_id]}"},
		             {:type => :cookie, :value => "token=#{@token}"}]
		
		if options[:targets].class() == String then
			scan_opts << {:value => "target=#{options[:targets]}"}
		elsif options[:targets].class() == Array then
			options[:targets].each do|target|
				scan_opts << {:value => "target=#{target}"}
			end
		else
			raise "Unknown target type #{options[:targets].class().name()}"
		end
		
		scan_reply = execute_command("scan/new",  scan_opts)
		return scan_reply.elements.inject("/reply/contents/scan/uuid", []) {|r, x| r << x.text}[0]
	end
	
	def scan_status(uuid)
		report = list_report(uuid)
		return "unknown" unless report
		
		return report["status"]
	end
	
	def list_reports()
		reply = execute_command("report/list", [{:type => :cookie, :value => "token=#{@token}"}])
		
		results = []
		reply.elements.each("/reply/contents/reports/report") do|elem|
			result = {}
			elem.elements.each do|subelem|
				result[subelem.name] = subelem.text
			end
			results << result
		end
		
		return results
	end
	
	def list_report(uuid)
		reports = list_reports()
		
		report = reports.reject {|rep| rep["name"] != uuid}
		
		return nil if report.length != 1
		
		return report[0]
	end
	
	def save_report(uuid, file)
		report = execute_command("file/report/download",
		                       [{:value => "report=#{uuid}"},
		                        {:type => :cookie, :value => "token=#{@token}"}],
		                       false)
		if report.elements.inject("/NessusClientData_v2", []) {|r, x| r << x}.empty? then
			raise "error during save_report"
		end
		
		File.open(file, 'w') {|file| file << report.to_s}
	end
	
	def delete_report(uuid)
		report = execute_command("report/delete",
		                       [{:value => "report=#{uuid}"},
		                        {:type => :cookie, :value => "token=#{@token}"}])
	end
	
	# Scan targets completely and return when scan is finished
	#
	# Note: Only one of :policy_id, :policy_name or :policy_file needs to be specified.
	# @param :targets Hosts to scan (String or Array of String)
	# @param :report_file Path to report file (String)
	# @param :policy_id Policy ID of policy to use (String)
	# @param :policy_name Name of policy to use (String)
	# @param :policy_file Path to policy file to import and use (String)
	# @param :delete_policy (optional) Delete policy when scan is finished (Boolean)
	# @param :delete_report (optional) Delete report when scan is finished (Boolean)
	def scan_targets(options)
		raise "Need parameter :targets" unless options[:targets]
		raise "Need parameter :report_file" unless options[:report_file]
		
		policy_id = ""
		
		if options[:policy_id] then
			policy_id = options[:policy_id]
		elsif options[:policy_name] then
			policy_ids = get_policy_ids(policy_name)
		
			raise "No policy with this name (#{policy_name}) found" if policy_ids.empty?
			raise "Several policies with this name (#{policy_name}) found" if policy_ids.length > 1
			policy_id = policy_ids[0]
		elsif options[:policy_file] then
			policy_id = import_policy_file(options[:policy_file])
		else
			raise "Need parameter :policy_file, :policy_name or :policy_id" 	
		end
		
		scan_uuid = start_scan(:policy_id => policy_id, :targets => options[:targets])
		while scan_status(scan_uuid) != "completed" do
			sleep 30
		end
		save_report(scan_uuid, options[:report_file])
		delete_policy(policy_id) if options[:delete_policy]
		delete_report(scan_uuid) if options[:delete_report]
		
		return scan_uuid
	end
	
	def logout()
		execute_command("logout",
		                [{:type => :cookie, :value => "token=#{@token}"}])
		@token = nil
	end
	
	def self.get_policy_name_from_file(file)
		return (Document.new(File.new(file)).elements.inject("NessusClientData_v2/Policy/policyName", []) {|r, x| r << x.text})[0]
	end
	
	# Allowed values for configuration keys are:
	#
	#  "policy_name": "some_name"
	#  "policy_shared": "0" if the policy is not shared, or "1" if it is shared
	#  "SSH settings[entry]:SSH user name :": "root"
	#  "SSH settings[file]:SSH private key to use :": {:type => :file, :file => "/tmp/key.pem"}
	#  "plugin_selection.family.Service detection": "enabled", "disabled", "mixed"
	#  "plugin_selection.individual_plugin.19679": "enabled", "disabled"
	#  "SSH settings[radio]:Elevate privileges with :": "Nothing", "sudo", "su", ...
	def new_policy(options)
		raise "missing option \"policy_name\"" unless options["policy_name"]
		raise "missing option \"policy_shared\"" unless options["policy_shared"]
		
		cmd_params = [{:type => :cookie, :value => "token=#{@token}"}]
		
		options.each do|key,value|
			if value.class() == String then
				cmd_params << {:value => "#{key}=#{value}"}
			elsif value.class() == Hash then
				if value[:type] == :file then
					filename = upload_file(value[:file])
					cmd_params << {:value => "#{key}=#{filename}"}
				else
					raise "Unknown value hash type '#{value[:type]}' for policy configuration key '#{key}'"
				end
			else
				raise "Unknown value type '#{value.class()} for policy configuration key '#{key}'"
			end
		end
		
		reply = execute_command("policy/add", cmd_params)
		policy_ids = reply.elements.inject("/reply/contents/policy/policyID", []) {|r, x| r << x.text}
		
		raise "Policy '#{options["policy_name"]}' already exists or was not imported (#{policy_ids.length()})" unless policy_ids.length() == 1
		
		return policy_ids[0]
	end
	
	def list_plugin_families()
		reply = execute_command("plugins/list",
		                        [{:type => :cookie, :value => "token=#{@token}"}])
		return reply.elements.inject("/reply/contents/pluginFamilyList/family/familyName", []) {|r, x| r << x.text}
	end
	
	def list_plugin_family(family_name)
		reply = execute_command("plugins/list/family",
		                        [{:type => :cookie, :value => "token=#{@token}"},
		                         {:value => "family=#{family_name}"}])
		results = []
		
		reply.elements.each("/reply/contents/pluginList/plugin") do|elem|
			result = {}
			elem.elements.each do|subelem|
				result[subelem.name] = subelem.text
			end
			results << result
		end
		return results
	end
end
