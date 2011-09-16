#require "RubyGems"
require "AWS"

require 'help/ec2_helper'
require 'test/unit'
require 'test/mock/mocked_ec2_api'

class TestEc2Helper < Test::Unit::TestCase
  def test_check_open_port
    ec2_api = MockedEc2Api.new
    ec2_api.create_security_group(:group_name => "default")    
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

  def test_lookup_security_group_names
    ec2_api = MockedEc2Api.new
    #create groups
    webgroup = ec2_api.create_security_group(:group_name => "web-services")
    ec2_api.authorize_security_group_ingress(:group_name => "web-services",
      :ip_protocol => "tcp", :from_port => 80, :to_port => 80, :cidr_ip => "0.0.0.0/0")
    ec2_api.authorize_security_group_ingress(:group_name => "web-services",
      :ip_protocol => "tcp", :from_port => 443, :to_port => 443, :cidr_ip => "0.0.0.0/0")
    ec2_api.authorize_security_group_ingress(:group_name => "web-services",
      :ip_protocol => "tcp", :from_port => 22, :to_port => 22, :cidr_ip => "0.0.0.0/0")
    thousand = ec2_api.create_security_group(:group_name => "thousand")
    ec2_api.authorize_security_group_ingress(:group_name => "thousand",
      :ip_protocol => "tcp", :from_port => 1000, :to_port => 1000, :cidr_ip => "0.0.0.0/0")
    ec2_api.authorize_security_group_ingress(:group_name => "thousand",
      :ip_protocol => "tcp", :from_port => 2000, :to_port => 2000, :cidr_ip => "0.0.0.0/0")
    #create instances
    image_id = "ami-12345"
    key_name = "eu-west-1"
    ec2_api.create_dummy_instance("i-11111", image_id,
      "running", "i1.ec2.amazonaws.com",
      "i1.ec2.amazonaws.com", key_name, ["web-services"])
    ec2_api.create_dummy_instance("i-22222", image_id,
      "running", "i1.ec2.amazonaws.com",
      "i1.ec2.amazonaws.com", key_name, ["thousand"])
    ec2_helper = Ec2Helper.new(ec2_api)
    instance_info1 = ec2_api.describe_instances(:instance_id => "i-11111")['reservationSet']['item'][0]
    instance_info2 = ec2_api.describe_instances(:instance_id => "i-22222")['reservationSet']['item'][0]
    puts "instance_info1 = #{instance_info1.inspect}"
    puts "instance_info2 = #{instance_info2.inspect}"
    assert_equal ["web-services"], ec2_helper.lookup_security_group_names(instance_info1)
    assert_equal ["thousand"], ec2_helper.lookup_security_group_names(instance_info2)
  end

  def test_lookup_open_ports
    ec2_api = MockedEc2Api.new
    #create groups
    webgroup = ec2_api.create_security_group(:group_name => "web-services")
    ec2_api.authorize_security_group_ingress(:group_name => "web-services",
      :ip_protocol => "tcp", :from_port => 80, :to_port => 80, :cidr_ip => "0.0.0.0/0")
    ec2_api.authorize_security_group_ingress(:group_name => "web-services",
      :ip_protocol => "tcp", :from_port => 443, :to_port => 443, :cidr_ip => "0.0.0.0/0")
    thousand = ec2_api.create_security_group(:group_name => "thousand")
    ec2_api.authorize_security_group_ingress(:group_name => "thousand",
      :ip_protocol => "tcp", :from_port => 1000, :to_port => 1000, :cidr_ip => "0.0.0.0/0")
    ec2_api.authorize_security_group_ingress(:group_name => "thousand",
      :ip_protocol => "tcp", :from_port => 2000, :to_port => 2000, :cidr_ip => "0.0.0.0/0")
    ec2_helper = Ec2Helper.new(ec2_api)
    group_infos = ec2_api.describe_security_groups()
    assert_equal [{:protocol => 'tcp', :port => 22},{:protocol => 'tcp', :port => 80},
      {:protocol => 'tcp', :port => 443}], ec2_helper.lookup_open_ports("web-services",group_infos)
    assert_equal [{:protocol => 'tcp', :port => 22},{:protocol => 'tcp', :port => 1000},
      {:protocol => 'tcp', :port => 2000}], ec2_helper.lookup_open_ports("thousand",group_infos)
  end

  def test_get_instance_id
    ec2_api = MockedEc2Api.new
    image_id = "ami-12345"
    key_name = "eu-west-1"
    ec2_api.create_dummy_instance("i-11111", image_id,
      "running", "i1.ec2.amazonaws.com",
      "i1.ec2.amazonaws.com", key_name)
    ec2_helper = Ec2Helper.new(ec2_api)
    assert_equal "i-11111", ec2_helper.get_instance_id(ec2_api.describe_instances()['reservationSet']['item'][0])
  end

end
