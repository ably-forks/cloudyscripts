require 'nessus-xmlrpc'

module NessusXMLRPC
	class NessusXMLRPCrexml
		def file_upload(file)
			cmd = "curl --max-time 120 --silent --insecure --cookie \"token=#{@token}\" --form \"Filedata=@#{file}\" #{@nurl}file/upload"
			print "Executing Nessus command: '#{cmd}'\n"
			body = `#{cmd}`
			
			docxml = REXML::Document.new(body)
			begin
				status = docxml.root.elements['status'].text
				filename = docxml.root.elements['contents'].elements['fileUploaded'].text
			rescue => err
				print "[e] Error in XML parsing\n"
			end
			
			if status == "OK" then
				return filename
			else
				return nil
			end
		end
		
		def policy_upload(policy_file)
			filename = file_upload(policy_file)
			
			if filename then
				cmd = "curl --max-time 120 --silent --insecure --cookie \"token=#{@token}\" --data \"file=#{filename}\" #{@nurl}file/policy/import"
				print "Executing Nessus command: '#{cmd}'\n"
				body = `#{cmd}`
			
				docxml = REXML::Document.new(body)
				begin
					status = docxml.root.elements['status'].text
				rescue => err
					print "[e] Error in XML parsing\n"
				end
			
				if status == "OK" then
					return docxml
				else
					return nil
				end
			else
				return nil
			end
		end
		
		def policy_delete(policy_id)
			cmd = "curl --max-time 120 --silent --insecure --cookie \"token=#{@token}\" --data \"policy_id=#{policy_id}\" #{@nurl}policy/delete"
			print "Executing Nessus command: '#{cmd}'\n"
			body = `#{cmd}`
			
			docxml = REXML::Document.new(body)
			begin
				status = docxml.root.elements['status'].text
			rescue => err
				print "[e] Error in XML parsing\n"
			end
			
			if status == "OK" then
				return true
			else
				return nil
			end
		end
		
		def policy_file_get_policies(policy_file)
			policy_names = []
			
			REXML::Document.new(File.read(policy_file)).root.each_element('//Policy') {|p| policy_names << p.elements['policyName'].text}
			return policy_names
		end
		
		def scan_execute(policy_file, policy_name, scan_name, target)
			while (policy_id = policy_get_id(policy_name)) != '' do
				policy_delete(policy_id)
			end
			
			policy_upload(policy_file)
			
			policy_id = policy_get_id(policy_name)
			
			if policy_id != '' then
				scan = scan_new(policy_id, scan_name, target)
				
				while scan_status(scan) == 'running' do
					sleep(5)
				end
				
				report = report_file_download(scan)
				report_delete(scan)
				policy_delete(policy_id)
				return report
			else
				return nil
				# error: policy not found altough just imported
			end
		end
	end
end
