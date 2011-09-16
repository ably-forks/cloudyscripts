require "base64"
require "xmlsimple"

class VCloudApiHandler
  def initialize(username, password, url_endpoint, logger = Logger.new(STDOUT))
    @username = username
    @password = password
    @url_endpoint = url_endpoint
    @logger = logger
  end

  def versions
    res = Net::HTTP.get "#{@url_endpoint}", '/api/versions'
    return XmlSimple.xml_in(res)
  end

  def login
    url = URI.parse("https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/login")    
    req = Net::HTTP::Post.new(url.path)
    req.basic_auth("#{@username}", "#{@password}")
    req.add_field('Content-Length','0')
    req.add_field('Content-Type', 'application/vdn.vmware.vCloud.orgList+xml')
    @logger.debug "--- Request-Header:"
    req.each_header do |key, name|
      @logger.debug "#{key}: #{name}"
    end
    res = http_request(url, req)
    @vcloud_token = res.get_fields("Set-Cookie")
    xmlbody = XmlSimple.xml_in(res.body)
    @organization_link = xmlbody["Org"].first["href"]
    return xmlbody
  end

  def org
    res = generic_get_request(@organization_link)
    xmlbody = XmlSimple.xml_in(res.body)
    xmlbody["Link"].each() {|info|
      @logger.info "org: found info on #{info.inspect}"
      case info['type']
        when "application/vnd.vmware.vcloud.vdc+xml"
          @vdc_link = info['href']
        when "application/vnd.vmware.vcloud.catalog+xml"
          @catalog_link = info['href']
        when "application/vnd.vmware.vcloud.tasksList+xml"
          @taskslist_link = info['href']
        when "application/vnd.tmrk.vcloudExpress.keysList+xml"
          @keyslist_link = info['href']
        else
          @logger.info "could not identify #{info['type']} for org"
      end
    }
    return xmlbody
  end

  def vdc
    @server_links = []
    @network_links = []    
    res = generic_get_request(@vdc_link)
    xmlbody = XmlSimple.xml_in(res.body)    
    xmlbody['ResourceEntities'].first['ResourceEntity'].each() do |info|
      @logger.info "vdc: found info on #{info.inspect}"
      case info['type']      
        when "application/vnd.vmware.vcloud.vApp+xml"
          @server_links << info['href']
      else
        @logger.info "could not identify #{info['type']} for vdc"
      end
    end
    @logger.debug "@server_links = #{@server_links.inspect}"
    xmlbody['AvailableNetworks'].first['Network'].each() do |info|
      @logger.debug "vdc: found info on #{info.inspect}"
      case info['type']
        when "application/vnd.vmware.vcloud.network+xml"
          @network_links << info['href']
      else
        @logger.info "could not identify #{info['type']} for vdc"
      end
    end
    @logger.debug "@network_links = #{@network_links.inspect}"
  end

  def v_apps
    @server_links.each() {|server_link|
      generic_get_request(server_link)
    }
  end

  def networks
    @network_links.each() {|network_link|
      generic_get_request(network_link)
    }
  end

  def internet_services
    @internet_services_link = "#{@vdc_link}/internetServices"
    @internet_services_link.gsub!("api/v0.8a-ext1.6","api/extensions/v1.6")
    res = generic_get_request(@internet_services_link)
    xmlbody = XmlSimple.xml_in(res.body)
    return xmlbody
  end

  def server_ip_address(server_ip)
    server_link = "https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/vapp/#{server_ip}"
    res = generic_get_request(server_link)
    xmlbody = XmlSimple.xml_in(res.body)
    ip_address = xmlbody["NetworkConnectionSection"].first["NetworkConnection"].first["IpAddress"]
    @logger.debug "Ip: #{ip_address}"
    #"NetworkConnectionSection"=>[{"NetworkConnection"=>[{"IpAddress"=>["10.114.117.11"],
    ip_address
  end

  def firewall_rules
    
  end

  #private

  def generic_get_request(full_url)
    raise Exception.new("no url") if full_url == nil
    @logger.debug "generic request: url = #{full_url.inspect}"
    url = URI.parse(full_url)
    req = Net::HTTP::Get.new(url.path)
    prepare_request(req)
    return http_request(url, req)
  end

  def prepare_request(request)
    raise Exception.new("no vcloud-token") if @vcloud_token == nil
    request.add_field('Content-Length','0')
    request.add_field('Content-Type', 'application/vdn.vmware.vCloud.orgList+xml')
    request.add_field('Cookie', @vcloud_token)
    
    @logger.debug "--- Request-Header:"
    request.each_header do |key, name|
      @logger.debug "#{key}: #{name}"
    end
  end

  def http_request(url, request)
    http_session = Net::HTTP.new(url.host, url.port)
    http_session.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http_session.use_ssl = true
    res = http_session.start {|http|
      http.request(request)
    }

    @logger.debug "--- Response-Header:"
    res.each_header do |key, name|
      @logger.debug "#{key}: #{name}"
    end
    xmlbody = XmlSimple.xml_in(res.body)
    @logger.debug "response-body: #{xmlbody.inspect}"
    return res
  end
end
