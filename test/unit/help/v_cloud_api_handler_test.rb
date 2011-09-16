require 'help/v_cloud_api_handler'
require 'test/unit'
require 'test/mock/mocked_v_cloud_api'

class VCloudApiHandlerTest < Test::Unit::TestCase
  def setup
    username = "matthias@secludit.com"
    password = "vcloud1125"
    api_endpoint = "services.vcloudexpress.terremark.com"
    @api = MockedVCloudApi.new(username, password, api_endpoint)
  end

  def test_versions
    res = @api.versions
    puts res.inspect
    assert_not_nil res["VersionInfo"]
  end

  def test_login
    res = @api.login
    puts res.inspect
  end

  def test_org
    res = @api.login
    res = @api.org
    puts res.inspect
  end

  def test_internet_services
    @api._create_internet_service("192.11.1.43", 80)
    res = @api.login
    #res = @api.org
    #res = @api.vdc
    res = @api.internet_services
    puts res.inspect
    #res = @api.generic_get_request("https://services.vcloudexpress.terremark.com/api/extensions/v1.6/publicIp/390289")
  end


end
