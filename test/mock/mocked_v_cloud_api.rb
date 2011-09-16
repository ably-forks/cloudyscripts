require 'logger'
require 'lib/help/v_cloud_api_handler'

# Already uses groupId in groups and instances, but still uses group_names for permissions

class MockedVCloudApi < VCloudApiHandler
  def drop(a)
    
  end

  def initialize(user, password, api_endpoint)
    super(user, password, api_endpoint)
    @orgs = [{:user => user, :id => rand(10000)}]
    @vdcs = [{:name => "Miami Environment", :id => rand(10000)}]
    @internet_services = []
  end

  def versions
    {"xmlns:xsd"=>"http://www.w3.org/2001/XMLSchema", "xmlns:xsi"=>"http://www.w3.org/2001/XMLSchema-instance", "VersionInfo"=>[{"Version"=>["0.8"], "LoginUrl"=>["https://services.vcloudexpress.terremark.com/api/v0.8/login"]}, {"Version"=>["0.8a-ext1.6"], "LoginUrl"=>["https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/login"]}], "xmlns"=>"http://www.vmware.com/vcloud/versions"}
  end

  def login
    puts "login successfull"
    res = {"xmlns:xsd"=>"http://www.w3.org/2001/XMLSchema",
     "Org"=>[],
     "xmlns:xsi"=>"http://www.w3.org/2001/XMLSchema-instance",
     "xmlns"=>"http://www.vmware.com/vcloud/v0.8"}
    orgs = res['Org']
    @orgs.each() {|org|
      orgs << {
        "name"=>"#{org[:user]}",
         "href"=>"https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/org/#{org[:id]}",
         "type"=>"application/vnd.vmware.vcloud.org+xml"
      }
    }
    res
  end

  def org()
    org = @orgs.first #TODO: change when several organizations supported
    result =
      {"name"=>"#{org[:user]}",
        "href"=>"https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/org/#{org[:id]}",
        "xmlns:xsd"=>"http://www.w3.org/2001/XMLSchema",
        "Link"=>[],
        "xmlns:xsi"=>"http://www.w3.org/2001/XMLSchema-instance", "xmlns"=>"http://www.vmware.com/vcloud/v0.8"}
    links = result["Link"]
    @vdcs.each() {|vdc|
      links << {
        "name"=> vdc[:name],
        "href"=>"https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/vdc/#{vdc[:id]}",
        "rel"=>"down", "type"=>"application/vnd.vmware.vcloud.vdc+xml"}
    }
    return result
  end

  def vdc
    
  end

  def get_vapps
    raise Exception.new("not yet implemented")
  end

  def internet_services
    result =
    {"xmlns:i"=>"http://www.w3.org/2001/XMLSchema-instance",
     "InternetService"=>[],
     "xmlns"=>"urn:tmrk:vCloudExpressExtensions-1.6"}
    iserv = result['InternetService']
    @internet_services.each() {|is|
      id = is[:id]
      iserv << {
        'Enabled' => ['true'],
        'Protocol' => ['XXX'],
        'Name' => ["Test Port #{is[:port]}"],
        "Href"=>["http://services.vcloudexpress.terremark.com/api/extensions/v1.6/internetService/#{id}"],
        "Port" => [is[:port]],
        "PublicIpAddress"=>[
          {"Name"=>["#{is[:ip]}"],
           "Href"=>["http://services.vcloudexpress.terremark.com/api/extensions/v1.6/publicIp/#{id*10}"],
           "Id"=>["#{id*10}"]}], "Timeout"=>["2"], "Id"=>["#{id}"], "Description"=>[{}]
      }
    }
    return result
  end

  def _create_vapp(config)
    @vapps << config
  end

  def _create_internet_service(ip, port, id = rand(10000))
    @internet_services << {:ip => ip, :port => port, :id => id}
  end

end
