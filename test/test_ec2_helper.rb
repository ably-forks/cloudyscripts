#require "RubyGems"
require "AWS"

require "help/ec2_helper"
require 'test/unit'
require 'test/mock/mocked_ec2_api'

class TestEc2Helper < Test::Unit::TestCase
  def test_check_open_port
    ec2_api = MockedEc2Api.new
    ec2_helper = Ec2Helper.new(ec2_api)
    res = ec2_helper.check_open_port("default", 22)
    puts "is port 22 open for default group? #{res}"
    assert res
    res = ec2_helper.check_open_port("default", 2211)
    puts "is port 2211 open for default group? #{res}"
    assert !res
    begin
      res = ec2_helper.check_open_port("quarkkugel", 2211)
      puts res
      assert false
    rescue Exception => e
      puts "checking quarkkugel leads to exception: #{e}"
      assert true
    end
  end
end