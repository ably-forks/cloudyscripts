#!/usr/bin/env ruby

require 'rexml/document'
require 'audit/lib/util/random_string'
require 'fileutils'
require 'socket'
require 'timeout'

# http://auntitled.blogspot.com/2010/07/identified-ubuntu-version-from-ssh.html

module SSH_FINGERPRINT
	TMP_DIRECTORY = '/tmp'
	
	# Create a name for a new temporary file and check that it does not exist yet.
	# Returns [String] Name of unused temporary file
	def self.get_temp_file()
		while true do
			file = TMP_DIRECTORY + '/' + RandomString::generate_name(20)
		 	if !File.exists?(file) then
				return file
			end
		end
	end
	
	# Exception during parsing.
	public
	class ParseException < Exception
	end
	
	# Exception during execution of an external program.
	public
	class ProgramExecutionException < Exception
	end
	
	# Use NMap to get information about server-supported algorithms
	# The result will be a dictionary of lists, where the dictionary key is the
	# name of the algorithm category (kex_algorithms, server_host_key_algorithms,
	# encryption_algorithms, mac_algorithms, compression_algorithms), and the
	# list stored under that key are the names of the algorithms supported for
	# that category. All text is received from the server, no change or matching
	# of the values is performed.
	# 
	# Parameter host [String] Name of the host to connect to
	# Parameter port [Integer] Target port
	#
	# Throws ProgramExecutionException if NMap does not exit with status code 0
	# Throws ParseException if there is unexpected output from NMap
	# Returns [Dictionary of String * Array of String] Dictionary of arrays of the supported algorithms
	#		Dictionary may be empty if there is no output from the NMap ssh2-enum-algos script.
	public
	def self.get_algorithms(host, port = 22)
		file = get_temp_file()
		
		exit_ok = system("nmap -p#{port} -v -Pn --script ssh2-enum-algos -oX #{file} #{host} 2>/dev/null 1>/dev/null")
		raise ProgramExecutionException, "NMap returned exit code #{$?} instead of 0" unless exit_ok
		
		xml_data = File.open(file, "r") {|f| f.read}
		FileUtils.rm_f(file)
		doc = REXML::Document.new(xml_data)
		
#		raise ParseException, "NMap ssh script did not execute" unless doc.elements["//script"] && doc.elements["//script"].attributes['output']
		return {} unless doc.elements["//script"] && doc.elements["//script"].attributes['output']
		
		algorithm_lines = doc.elements['//script'].attributes['output'].lines

		algorithms = {}
		current_section = nil
		algorithm_lines.each do|line|
			if /^  ([a-z_]+) \([0-9]+\)$/.match(line) then
				current_section = $1
				algorithms[current_section] = []
			elsif /^      ([a-zA-Z0-9_@.=+-]+)$/.match(line) then
				raise ParseException, "algorithm line not preceded by an algorithm type section: '#{line}'" if current_section.nil?
				algorithms[current_section] << $1
			else
				if line.strip() != "" then
					raise ParseException, "unexpected line in nmap output: '#{line}'"
				end
			end
		end

		return algorithms
	end
	
	# Use NMap to get host key information from a remote machine
	# The retrieved host keys are stored in an array of dictionaries,
	# one dictionary for each key:
	# - <b>:length</b> is the key length in bits
	# - <b>:fingerprint</b> is the key's fingerprint
	# - <b>:type</b> is the key's algorithm from the fingerprint line
	# - <b>:ssh_type</b> is the key's algorithm from the key line
	# - <b>:key</b> is the base-64 encoded key data of the host key
	#
	# Parameter host [String] Name or address of the host to connect to
	# Parameter port [Integer] Target port
	#
	# Throws a ParseException if any of NMap's output does not conform to expectations
	# Throws a ProgramExecutionException if the system call for NMap does not return 0 as exit code
	# Returns [Array of Dictionary of Symbol * String] an array of above-described dictionaries
	public
	def self.get_host_keys(host, port = 22)
		file = get_temp_file()
		
		exit_ok = system("nmap -p#{port} -v -Pn --script ssh-hostkey -oX #{file} #{host} 2>/dev/null 1>/dev/null")
		raise ProgramExecutionException, "NMap returned exit code #{$?} instead of 0" unless exit_ok
		
		xml_data = File.open(file, "r") {|f| f.read}
		FileUtils.rm_f(file)
		doc = REXML::Document.new(xml_data)
		
#		raise ParseException, "NMap ssh script did not execute" unless doc.elements["//script"] && doc.elements["//script"].attributes['output']
		return [] unless doc.elements["//script"] && doc.elements["//script"].attributes['output']
		
		keys_lines = doc.elements['//script'].attributes['output'].lines

		line_type = :fingerprint_line
		
		keys = []
		current_key = nil
		keys_lines.each do|line|
			line = line.strip
			if line_type == :fingerprint_line then
				line_type = :key_line
				match = /^([0-9]+) ([0-9a-f:]+) (\([A-Z0-9]+\))$/.match(line)
				if match then
					raise ParseException, "current_key is not nil, it should be" unless current_key.nil?
					
					current_key = {:length => match[1], :fingerprint => match[2], :type => match[3]}
				else
					raise ParseException, "Unexpected line '#{line}', expected fingerprint line"
				end
			else
				line_type = :fingerprint_line
				match = /^([a-z0-9_-]+) ([A-Za-z0-9+\/=]+)$/.match(line)
				if match then
					raise ParseException, "current_key is nil, it shouldn't be" if current_key.nil?
					
					current_key[:ssh_type] = match[1]
					current_key[:key] = match[2]
					keys << current_key
					current_key = nil
				else
					raise ParseException, "Unexpected line '#{line}', expected key line"
				end
			end
		end
		
		raise ParseException, "current_key is not nil, it should be" unless current_key.nil?
		return keys
	end
	
	# Get the server banner from the server
	# The server banner usually announces the supported SSH version as well as the operating
	# system
	#
	# Parameter host [String] The target host to connect to
	# Parameter port [Integer] Target port
	# Parameter timeout [Integer] Timeout in seconds
	#
	# Returns [String/:TIMEOUT] The banner announced by the server or :TIMEOUT if the connect times
	#		out; :HOST_UNREACHABLE if destination host is unreachable
	public 
	def self.get_banner(host, port = 22, timeout = 5)
		begin
			timeout(timeout) do
				sock = TCPSocket.new(host, port)
				sock.puts "SSH-2.0-OpenSSH_5.3p1 Debian-3ubuntu5\r\n"
				banner = sock.readline
				sock.close
				return banner
			end
		rescue Errno::EHOSTUNREACH
			return :HOST_UNREACHABLE
		rescue Errno::ECONNREFUSED
			return :CONNECTION_REFUSED
		rescue Timeout::Error
		end
		
		return :TIMEOUT
	end
	
	# Test if protocol version 1 is supported by the server
	#
	# Parameter host [String] The target host to connect to
	# Parameter port [Integer] Target port
	# Parameter timeout [Integer] Timeout in seconds
	#
	# Returns [Boolean/:TIMEOUT] <b>true</b> if remote server supports protocol version 1, <b>false</b> if
	#		protocol version 1 is not supported. :TIMEOUT if the connection times out; :HOST_UNREACHABLE if destination host is unreachable
	def self.version1_supported?(host, port = 22, timeout = 5)
		begin
			timeout(timeout) do
				sock = TCPSocket.new(host, port)
				sock.puts "SSH-1.5-OpenSSH_5.3p1 Debian-3ubuntu5\r\n"
				banner = sock.readline
				data = sock.read(13)
				sock.close
				return /^....[\x00]+\x02/.match(data) != nil
			end
		rescue Errno::EHOSTUNREACH
			return :HOST_UNREACHABLE
		rescue Errno::ECONNREFUSED
			return :CONNECTION_REFUSED
		rescue Timeout::Error
		end
		
		return :TIMEOUT
	end
	
	public
	def self.fingerprint(host, port = 22)
		return {
			:host => host,
			:port => port,
			:banner => get_banner(host, port),
			:host_keys => get_host_keys(host, port),
			:algorithms => get_algorithms(host, port),
			:version1 => version1_supported?(host, port)}
	end
end
