require 'timeout'
require 'socket'

# http://www.apachehaus.com/index.php?option=com_content&view=article&id=119:history-releases-apache&catid=41:catagory-change-logs&Itemid=93

#Contains code to take responses to revealing HTTP requests.
#This code needs Ruby 1.9 for the timeout module.
module HTTP_FINGERPRINT
	#HTTP request timeout in seconds
	HTTP_REQUEST_TIMEOUT = 10
	
	def self.repeat_character(x, y)
		if y == 0 then
			return ""
		else
			return x + repeat_character(x, y - 1)
		end
	end
	
	@http_methods = [["GET / HTTP/1.1\r\n", :get_existing],
                ["GET /" + repeat_character("x", 1024) + " HTTP/1.1\r\n", :get_long],
                ["GET /kC8CH9.html HTTP/1.1\r\n", :get_nonexisting],
                ["GET / HTTP/9.8\r\n", :wrong_version],
                ["GET / INVD/1.1\r\n", :wrong_protocol],
                ["HEAD / HTTP/1.1\r\n", :head_existing],
                ["OPTIONS / HTTP/1.1\r\n", :options],
                ["DELETE / HTTP/1.1\r\n", :delete_existing],
                ["GET /etc/passwd?format=%%%&xss=\"><script>alert('xss');" + 
                "</script>&traversal=../../&sql='%20OR%201; HTTP/1.1\r\n", :attack_request],
                ["TEST / HTTP/1.1\r\n", :wrong_method],
                ["GET \\ HTTP/1.1\r\n", :get_backslash_resource]]
	
	def self.fingerprint_to_xml(fingerprint)
		xml = [
			"<scan_targethost>\n",
			fingerprint[:scan_targethost] + "\n",
			"</scan_targethost>\n",
			"<scan_targetport>\n",
			fingerprint[:scan_targetport].to_s + "\n",
			"</scan_targetport>\n",
			"<scan_targetsecure>\n",
			fingerprint[:scan_targetsecure].to_s + "\n",
			"</scan_targetsecure>\n",
			"<scan_date>\n",
			fingerprint[:scan_timestamp].strftime("%d.%m.%Y") + "\n",
			"</scan_date>\n",
			"<scan_time>\n",
			fingerprint[:scan_timestamp].strftime("%H:%M:%S") + "\n",
			"</scan_time>\n"]
		@http_methods.each do|method|
			xml << ("<" + method[1].to_s + ">\n")
			fingerprint[method[1]].each {|l| xml << l}
			xml << ("</" + method[1].to_s + ">\n")
		end
		
		return xml.join
	end
	
	public
	def self.fingerprint(host, port = 80, useragent = "(KHTML, like Gecko) " + 
	             "Ubuntu/10.04 Chromium/8.0.552.224 Chrome/8.0.552.224" + 
                " Safari/534.10")
		header_lines = ["User-Agent: " + useragent  + "\r\n",
	               "Host: " + host + "\r\n",
                  "Connection: Close\r\n",
                  "Cache-Control: no-cache\r\n",
                  "\r\n"]
		http_fingerprints= {
				:scan_targethost => host,
				:scan_targetport => port,
				:scan_targetsecure => 0,
				:scan_timestamp => Time.now}
#				[
#			"<scan_targethost>\n",
#			host + "\n",
#			"</scan_targethost>\n",
#			"<scan_targetport>\n",
#			port.to_s + "\n",
#			"</scan_targetport>\n",
#			"<scan_targetsecure>\n",
#			"0\n",
#			"</scan_targetsecure>\n",
#			"<scan_date>\n",
#			Time.now.strftime("%d.%m.%Y") + "\n",
#			"</scan_date>\n",
#			"<scan_time>\n",
#			Time.now.strftime("%H:%M:%S") + "\n",
#			"</scan_time>\n"]
		
		@http_methods.each do|method|
			http_fingerprints[method[1]] = []
#			http_fingerprints << ("<" + method[1] + ">\n")
			begin
				timeout(HTTP_REQUEST_TIMEOUT) do
					socket = TCPSocket.new(host, port)
					socket.puts method[0]
					header_lines.each do|hdr_line|
						socket.puts hdr_line
					end
	
					received = socket.readlines
					for i in 0 .. received.length
						if received[i] == "\r\n" || received[i] == "\n" then
							break
						end
						http_fingerprints[method[1]] << received[i]
					end
				end
			rescue Timeout::Error
				http_fingerprints[method[1]] = :TIMEOUT
			end
#			http_fingerprints << ("</" + method[1] + ">\n")
		end
		return http_fingerprints
	end
end