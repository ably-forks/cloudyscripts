#!/usr/bin/env ruby

require 'my_option_parser'

# Parsed options from command line
options = MyOptionParser.new(ARGV).parse()

print "Connection type: #{options.connection_type}\n"
print "SSH Credentials: #{options.ssh_credentials.to_s}\n" if options.connection_type == :ssh
#print "SSH: #{options[:ssh]}\n" unless options[:ssh].nil?
	
	
	                