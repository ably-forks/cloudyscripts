require 'logger'
require 'lib/help/v_cloud_api_handler'

# Already uses groupId in groups and instances, but still uses group_names for permissions

class MockedVCloudApi < VCloudApiHandler
  def drop(a)
    
  end

  def versions
    {"xmlns:xsd"=>"http://www.w3.org/2001/XMLSchema", "xmlns:xsi"=>"http://www.w3.org/2001/XMLSchema-instance", "VersionInfo"=>[{"Version"=>["0.8"], "LoginUrl"=>["https://services.vcloudexpress.terremark.com/api/v0.8/login"]}, {"Version"=>["0.8a-ext1.6"], "LoginUrl"=>["https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/login"]}], "xmlns"=>"http://www.vmware.com/vcloud/versions"}
  end

  def login
  end

  def get_vapps
  end

  def _create_vapp(config)
    @vapps << config
  end

end
