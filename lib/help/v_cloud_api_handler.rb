require "base64"
require "xmlsimple"

class VCloudApiHandler
  def initialize(username, password, url_endpoint)
    @username = username
    @password = password
    @url_endpoint = url_endpoint
    @debug = true
  end

  def versions
    res = Net::HTTP.get "#{@url_endpoint}", '/api/versions'
    return XmlSimple.xml_in(res)
  end

  def login
    url = URI.parse("https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/login")    
    puts "host = #{url.host}"
    puts "url.path=#{url.path}"
    puts "url.port=#{url.port}"
    req = Net::HTTP::Post.new(url.path)
    req.basic_auth("#{@username}", "#{@password}")
    req.add_field('Content-Length','0')
    req.add_field('Content-Type', 'application/vdn.vmware.vCloud.orgList+xml')
    puts "--- Request-Header:"
    req.each_header do |key, name|
      puts "#{key}: #{name}"
    end
    puts "------------"
    res = http_request(url, req)
    @vcloud_token = res.get_fields("Set-Cookie")
    puts "Set-Cookie Field: #{res.get_fields("Set-Cookie")}"
    puts "---------------------------------------"
    xmlbody = XmlSimple.xml_in(res.body)
    @organization_link = xmlbody["Org"].first["href"]
    return xmlbody
  end

  def org
    res = generic_get_request(@organization_link)
    xmlbody = XmlSimple.xml_in(res.body)
    puts "---------------------------------------"
    xmlbody["Link"].each() {|info|
      puts "org: found info on #{info.inspect}"
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
          puts "could not identify #{info['type']} for org"
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
      puts "vdc: found info on #{info.inspect}"
      case info['type']      
        when "application/vnd.vmware.vcloud.vApp+xml"
          @server_links << info['href']
      else
        puts "could not identify #{info['type']} for vdc"
      end
    end
    puts "@server_links = #{@server_links.inspect}"
    xmlbody['AvailableNetworks'].first['Network'].each() do |info|
      puts "vdc: found info on #{info.inspect}"
      case info['type']
        when "application/vnd.vmware.vcloud.network+xml"
          @network_links << info['href']
      else
        puts "could not identify #{info['type']} for vdc"
      end
    end
    puts "@network_links = #{@network_links.inspect}"
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
  end

  def server_ip_address(server_ip)
    server_link = "https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/vapp/#{server_ip}"
    res = generic_get_request(server_link)
    xmlbody = XmlSimple.xml_in(res.body)
    ip_address = xmlbody["NetworkConnectionSection"].first["NetworkConnection"].first["IpAddress"]
    puts "Ip: #{ip_address}"
    #"NetworkConnectionSection"=>[{"NetworkConnection"=>[{"IpAddress"=>["10.114.117.11"],
    ip_address
  end

  def firewall_rules
    
  end

  private

  def generic_get_request(full_url)
    puts "########################"
    raise Exception.new("no url") if full_url == nil
    puts "url = #{full_url.inspect}"
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
    if @debug
      puts "--- Request-Header:"
      request.each_header do |key, name|
        puts "#{key}: #{name}"
      end
    end
  end

  def http_request(url, request)
    http_session = Net::HTTP.new(url.host, url.port)
    http_session.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http_session.use_ssl = true
    res = http_session.start {|http|
      http.request(request)
    }
    if @debug
      puts "--- Response-Header:"
      res.each_header do |key, name|
        puts "#{key}: #{name}"
      end
      xmlbody = XmlSimple.xml_in(res.body)
      puts "response-body: #{xmlbody.inspect}"
    end
    return res
  end
end
