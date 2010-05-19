require "AWS"

# Implements some helper methods around the EC2 API and methods that are
# not yet implemented in the amazon-ec2 gem

class AWS::EC2::Base
  def describe_instance_attribute(options)
    params = {}
    params["InstanceId"] = options[:instance_id].to_s
    params["Attribute"] = "rootDeviceName" unless options[:attributes][:rootDeviceName] == nil
    return response_generator(:action => "DescribeInstanceAttribute", :params => params)
  end
end

class Ec2Helper
  # expects an instance of AWS::EC2::Base from the amazon-ec2 gem
  def initialize(ec2_api)
    @ec2_api = ec2_api
  end

  # Checks if the specified volume is acting as a root-device for the instance
  # to which it is attached. It therefore first calls ec2_describe_volumes() to
  # retrieve the instance linked to the volume specified, then calls
  # ec2_describe_instance_attribute() to retrieve the rootDeviceName of that
  # instance, and finally calls describe_instances() to retrieve all volumes
  # to check against volume_id and rootDeviceName.
  def is_root_device?(volume_id)
    vols = @ec2_api.describe_volumes(:volume_id => volume_id)
    if vols['volumeSet']['item'][0]['attachmentSet'] == nil || vols['volumeSet']['item'][0]['attachmentSet']['item'].size == 0
      #not linked to any instance, cannot be a root-device
      return false
    end
    instance_id = vols['volumeSet']['item'][0]['attachmentSet']['item'][0]['instanceId']
    res = @ec2_api.describe_instance_attribute(:instance_id => instance_id, :attributes => {:rootDeviceName => true})
    if res["rootDeviceName"] == nil
      return false
    end
    rdn = res['rootDeviceName']['value']
    res = @ec2_api.describe_instances(:instance_id => instance_id)
    if res['reservationSet']['item'][0]['instancesSet']['item'][0]['blockDeviceMapping']['item'].size == 0
      # volume unattached in the meantime
      return false
    end
    attached = res['reservationSet']['item'][0]['instancesSet']['item'][0]['blockDeviceMapping']['item']
    attached.each() {|ebs|
      volume = ebs['ebs']['volumeId']
      device_name = ebs['deviceName']
      if volume == volume_id && rdn == device_name
        return true
      end
    }
    return false
  end

  def get_attached_volumes(instance_id)
    instances = @ec2_api.describe_instances(:instance_id => instance_id)
    begin
      if instances['reservationSet']['item'][0]['instancesSet']['item'].size == 0
        raise Exception.new("instance #{instance_id} not found")
      end
      puts "instances = #{instances.inspect}"
      puts "attachments: #{instances['reservationSet']['item'][0]['instancesSet']['item'][0]['blockDeviceMapping']['item'].inspect}"
      attached = instances['reservationSet']['item'][0]['instancesSet']['item'][0]['blockDeviceMapping']['item'].collect() { |item|
        #
        puts "item = #{item['ebs'].inspect}"
        item['ebs']
      }
      puts "going to return #{attached.size.to_s}"
      return attached
    rescue Exception => e
      puts "exception: #{e.inspect}"
      puts e.backtrace.join("\n")
      raise Exception.new("error during retrieving attachments from instance #{instance_id} not found")
    end
  end

  def volume_prop(volume_id, prop)
    vols = @ec2_api.describe_volumes(:volume_id => volume_id)
    if vols['volumeSet']['item'].size == 0
      raise Exception.new("volume #{volume_id} not found")
    end
    return vols['volumeSet']['item'][0][prop.to_s]
  end

  def snapshot_prop(snapshot_id, prop)
    snaps = @ec2_api.describe_snapshots(:snapshot_id => snapshot_id)
    begin
      if snaps['snapshotSet']['item'].size == 0
        raise Exception.new("snapshot #{snapshot_id} not found")
      end
      return snaps['snapshotSet']['item'][0][prop.to_s]
    rescue
      raise Exception.new("snapshot #{snapshot_id} not found")
    end
  end

  def ami_prop(ami_id, prop)
    amis = @ec2_api.describe_images(:image_id => ami_id)
    begin
      if amis['imagesSet']['item'].size == 0
        raise Exception.new("image #{ami_id} not found")
      end
      return amis['imagesSet']['item'][0][prop.to_s]
    rescue
        raise Exception.new("image #{ami_id} not found")
    end
  end

  def instance_prop(instance_id, prop)
    instances = @ec2_api.describe_instances(:instance_id => instance_id)
    begin
      if instances['reservationSet']['item'][0]['instancesSet']['item'].size == 0
        raise Exception.new("instance #{instance_id} not found")
      end
      return instances['reservationSet']['item'][0]['instancesSet']['item'][0][prop.to_s]
    rescue
      raise Exception.new("instance #{instance_id} not found")
    end
  end

  # Checks if all ports are opened for the security group on range "0.0.0.0/0".
  # If an additional range is specified in the parameter, a check returns
  # true if a port is opened for either range 0.0.0.0/0 or the additional
  # range specified.
  # Returns true or false.
  def check_open_port(security_group, port, range = "0.0.0.0/0")
    res = @ec2_api.describe_security_groups(:group_name => security_group)
    puts "describe_security_groups = #{res.inspect} on #{@ec2_api.inspect}"
    groups = res['securityGroupInfo']['item']
    if groups.size == 0
      raise Exception.new("security group #{security_group} not found")
    end
    permissions = groups[0]['ipPermissions']['item']
    if permissions.size == 0
      # no permissions at all
      return false
    end
    permissions.each() {|permission|
      from_port = permission['fromPort'].to_i
      to_port = permission['toPort'].to_i
      prot = permission['ipProtocol']
      if port >= from_port && port <= to_port && prot == "tcp"
        permission['ipRanges']['item'].each() {|ipRange|
          if ipRange['cidrIp'] != "0.0.0.0/0" && ipRange['cidrIp'] != range
            next
          else
            return true
          end
        }
      end
    }
    false
  end

end
