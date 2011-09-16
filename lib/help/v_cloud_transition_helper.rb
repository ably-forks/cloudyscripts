require 'net/scp'

# Contains methods that are used by the scripts in the state-machines. Since
# they are reused by different scripts, they are factored into this module
module VCloudTransitionHelper

  def retrieve_ip_services
    @context[:vcloud_internet_services] = []
    vcloud_api_handler.login
    vcloud_api_handler.org
    vcloud_api_handler.vdc
    res = vcloud_api_handler.internet_services
    puts "retrieved: #{res.inspect}"
    res['InternetService'].each() {|is|
      port = is['Port'].first.to_i
      ip = is['PublicIpAddress'].first['Name'].first #TODO: several IPs may be defined here?
      id = is['PublicIpAddress'].first['Id'].first
      @context[:vcloud_internet_services] << {:port => port, :ip => ip, :id => id}
    }
  end

  protected

  #setting/retrieving handlers

  def remote_handler()
    if @remote_handler == nil
      if @context[:remote_command_handler] == nil
        @context[:remote_command_handler] = RemoteCommandHandler.new
      else
        @remote_handler = @context[:remote_command_handler]
      end
    end
    @remote_handler
  end

  def remote_handler=(remote_handler)
    @remote_handler = remote_handler
  end

  def vcloud_api_handler()
    if @vcloud_api_handler == nil
      @vcloud_api_handler = @context[:vcloud_api_handler]
    end
    @vcloud_api_handler
  end

  def vcloud_api_handler=(vcloud_api_handler)
    @vcloud_api_handler = vcloud_api_handler
  end

  def post_message(msg)
    if @context[:script] != nil
      @context[:script].post_message(msg)
    end
  end

end
