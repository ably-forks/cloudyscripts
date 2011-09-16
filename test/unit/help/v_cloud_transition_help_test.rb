require 'help/v_cloud_transition_helper'
require 'test/unit'
require 'test/mock/mocked_v_cloud_api'

class Dummy
  attr_accessor :context
  include VCloudTransitionHelper
  def initialize(api)
    @context = {}
    @context[:vcloud_api_handler] = api
    @context[:logger] = Logger.new(STDOUT)
  end
end

class VCloudTransitionHelperTest < Test::Unit::TestCase
  def setup
    username = "matthias@secludit.com"
    password = "vcloud1125"
    api_endpoint = "services.vcloudexpress.terremark.com"
    @api = MockedVCloudApi.new(username, password, api_endpoint)
  end

  def test_retrieve_internet_services
    @api._create_internet_service("1.2.3.4", 443)
    sth = Dummy.new(@api)
    sth.retrieve_ip_services
    puts "#{sth.context.inspect}"
    puts "#{sth.context[:vcloud_internet_services].inspect}"    
    assert_not_nil sth.context[:vcloud_internet_services]
    assert_equal 443, sth.context[:vcloud_internet_services].first[:port]
    assert_equal "1.2.3.4", sth.context[:vcloud_internet_services].first[:ip]
  end

end
