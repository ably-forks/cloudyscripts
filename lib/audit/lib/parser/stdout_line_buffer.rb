# To change this template, choose Tools | Templates
# and open the template in the editor.
#require 'pp'


class StdoutLineBuffer
  def initialize(connection)

    #puts "DEBUG: StdoutLineBuffer on connection #{connection}"    
    @buffer = ""
    connection.on_stdout do|msg|
      #puts "DEBUG: Buffer: '#{msg}'"
      @buffer += msg
      #puts "DEBUG: Buffer size: #{msg.length}, #{@buffer.length}"
      if @buffer[-1] == "\n" || @buffer =~ /\n$/ then
        #puts "DEBUG: endline detected using Array Class or using regexp"
        lines = @buffer.split("\n")
        @buffer = ""
      elsif @buffer =~ /^.+$/ then
        #puts "DEBUG: endline detected using regexp"
        lines = @buffer.split("\n")
        @buffer = ""
      else
        #puts "DEBUG: no endline detected"
        #puts "DEBUG: hexa buffer: #{@buffer.inspect}"
        #@buffer.each_byte {|c| print c, ' ' }
        #puts "\n"
        lines = @buffer.split("\n")
        @buffer = lines[-1]
        lines = lines[0 ... -1]
      end

      lines.each do|line|
        #puts "DEBUG: line: '#{line}'"
        @handler.call(line + "\n") unless @handler.nil?
      end
    end
  end

  def on_line(&block)
    @handler = block
  end
end
