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

  def volume_prop(volume_id, prop)
    vols = @ec2_api.describe_volumes(:volume_id => volume_id)
    if vols['volumeSet']['item'].size == 0
      raise Exception.new("volume #{volume_id} not found")
    end
    return vols['volumeSet']['item'][0][prop.to_s]
  end

  def snapshot_prop(snapshot_id, prop)
    snaps = @ec2_api.describe_snapshots(:snapshot_id => snapshot_id)
    if snaps['snapshotSet']['item'].size == 0
      raise Exception.new("snapshot #{snapshot_id} not found")
    end
    return snaps['snapshotSet']['item'][0][prop.to_s]
  end
end
