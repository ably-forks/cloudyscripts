require 'logger'
require 'pp'

# Already uses groupId in groups and instances, but still uses group_names for permissions

class MockedEc2Api
  attr_accessor :volumes, :next_volume_id, :fail, :logger, :rootDeviceType, :provoke_authfailure

  def drop(a)
    puts "#{a}"  
  end

  def initialize
    @volumes = []
    @instances = []
    @fail = false
    @next_volume_id = nil
    @snapshots = []
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::ERROR
    @rootDeviceType = "instance-store"
    @security_groups = []
    @permissions = {}
    @vpcs = []
    @igws = []
    #create_security_group(:group_name => "default")
    @images = []
  end

  def delete_security_group(options)
    found = lookup_group(options)
    drop "-- mock_ec2_api: delete_security_group #{found.inspect}"
    @security_groups.delete(found)
    @permissions.delete(found[:group_name])
  end

  #:instance_id, :key, :value
  def create_tag(options)
    drop "create_tag: #{options.inspect}"
    instance = get_instance(options[:instance_id])
    instance[:tagSet] << {:key => options[:key], :value => options[:value]}
  end

  def create_security_group(options)
    if options[:group_name] == nil
      raise Exception.new("must specify :group_name option")
    end
    return unless lookup_group(options) == nil
    group_name = options[:group_name]
    group_id = "sg-#{rand(999999)}"
    drop "-- mock_ec2_api: create_security_group #{options.inspect} group_id = #{group_id}"
    @security_groups << {:group_name => group_name, :group_id => group_id}
    @permissions[group_name] = []
    if options[:empty] == nil
      options = {:group_name => group_name, :ip_protocol => "tcp", :to_port => 22,
        :from_port => 22, :cidr_ip => "0.0.0.0/0"}
      authorize_security_group_ingress(options)
    end
  end

  def create_vpc_security_group(options)
    if options[:group_name] == nil
      raise Exception.new("must specify :group_name option")
    end
    return unless lookup_group(options) == nil
    group_name = options[:group_name]
    group_id = "sg-#{rand(999999)}"
    vpc_id = options[:vpc_id] 
    drop "-- mock_ec2_api: create_vpc_security_group #{options.inspect} group_id = #{group_id}, vpc_id = #{vpc_id}"
    @security_groups << {:group_name => group_name, :group_id => group_id, :vpc_id => vpc_id}
    @permissions[group_name] = []
    if options[:empty] == nil
      options = {:group_name => group_name, :ip_protocol => "tcp", :to_port => 22,
        :from_port => 22, :cidr_ip => "0.0.0.0/0"}
      authorize_security_group_ingress(options)
    end
  end

  def revoke_security_group_ingress(options)
    group_name = options[:group_name]
    protocol = options[:ip_protocol]
    from_port = options[:from_port]
    to_port = options[:to_port]
    cidr_ip = options[:cidr_ip]
    drop "@security_groups[group_name]: #{@permissions[group_name].inspect}"
    @permissions[group_name].each do |perm|
        drop "perm[:from_port] == from_port: #{perm[:from_port]} == #{from_port}?"
        drop "perm[:to_port] == to_port: #{perm[:to_port]} == #{to_port}?"
        drop "perm[:cidr_ip] == cidr_ip : #{perm[:cidr_ip].inspect} == #{cidr_ip.inspect}?"
        drop "perm[:ip_protocol] == protocol: #{perm[:ip_protocol]} == #{protocol}?"
    end
    @permissions[group_name].delete_if do |perm|
      perm[:from_port] == from_port &&
        perm[:to_port] == to_port &&
        perm[:cidr_ip] == cidr_ip &&
        perm[:ip_protocol] == protocol
    end
  end

  def authorize_security_group_ingress(options)
    drop "-- mock_ec2_api: authorize_security_group_ingress #{options.inspect}"
    group_name = options[:group_name]
    protocol = options[:ip_protocol]
    from_port = options[:from_port]
    to_port = options[:to_port]
    ip_ranges = options[:cidr_ip]
    #TODO: handling of groups
    permissions = @permissions[group_name]
    if permissions == nil
      permissions = []
      @permissions[group_name] = permissions
    end
    perm = {}
    perm[:from_port] = from_port
    perm[:to_port] = to_port
    perm[:ip_protocol] = protocol
    perm[:cidr_ip] = ip_ranges
    permissions << perm
  end

  def run_instances(options = {})
    instance_id = "i-from-#{options[:image_id]}"
    create_dummy_instance(instance_id, options[:image_id], "running",
      "who.cares", "public.dns.name", options[:key_name], [options[:security_group]])
    #XXX: create root volume for EBS-backed AMI
    #if @rootDeviceType == "ebs"
    ami = describe_images(:image_id => options[:image_id])
    if ami['imagesSet']['item'][0]['rootDeviceType'].eql?("ebs")
      vol_id = create_dummy_volume("vol-ebs-for-#{instance_id}", "timezone")['volumeId']
      attach_volume(:volume_id => vol_id, :instance_id =>instance_id, :device => ami['imagesSet']['item'][0]['rootDeviceName'])
      #drop "instances now #{describe_instances(:instance_id => instance_id).inspect}"
      puts "instances now #{describe_instances(:instance_id => instance_id).inspect}"
      #drop "volumes now #{describe_volumes(:volume_id => vol_id).inspect}"
      puts "volumes now #{describe_volumes(:volume_id => vol_id).inspect}"
    end
    describe_instances(:instance_id => instance_id)['reservationSet']['item'][0]
  end

  def describe_security_groups(options = {})
    cause_failure()
    groups = @security_groups
    group_name = options[:group_name] || "XXX"
    group_id = options[:group_id] || "XXX"
    drop "- mockgroups found = #{groups.inspect}"
    if options[:group_name] != nil
      groups = groups.select() {|g|
        g[:group_name] == group_name || g[:group_id] == group_id
      }
      drop "groups selected = #{groups.inspect}"
    end
    drop "mocked_ec2_api.describe_security_groups identified #{groups.inspect}"
    @logger.debug "mocked_ec2_api.describe_security_groups identified #{groups.inspect}"
    res = transform_secgroups(groups)
    res
  end

  def transform_secgroups(secgroups)
    drop "-- mock_ec2_api: format security group permissions #{secgroups.inspect}"
    ret = {}
    ret['securityGroupInfo'] = {}
    ret['securityGroupInfo']['item'] = []
    secgroups.each() {|sg|
      group_name = sg[:group_name]
      group_id = sg[:group_id]
      #
      group = {}
      group['groupName'] = group_name
      group['groupId'] = group_id
      ret['securityGroupInfo']['item'] << group
      group['ownerId'] = "945722764978"
      # add VPC ID if any
      if !sg[:vpc_id].nil?
        puts "Setting VPC ID: #{sg[:vpc_id]}"
        group['vpcId'] = sg[:vpc_id]
      end
      group['ipPermissions'] = {}
      group['ipPermissions']['item'] = []
      @permissions[group_name].each() {|p|
        perm = {}
        perm['groups'] = nil
        perm['fromPort'] = p[:from_port]
        perm['toPort'] = p[:to_port]
        perm['ipProtocol'] = p[:ip_protocol]
        perm['ipRanges'] = {}
        perm['ipRanges']['item'] = []
        p[:cidr_ip].each() {|range|
          ranges = {}
          perm['ipRanges']['item'] << ranges
          ranges['cidrIp'] = range
        }
        group['ipPermissions']['item'] << perm
      }
    }
    ret
  end

  # Expects either no params or an hash {:instance_id => [ids]}
  def describe_instances(instance_ids = nil)
    if instance_ids != nil
      #needed to adapt to the API
      instance_ids = instance_ids[:instance_id]
    else
      instance_ids = []
    end
    @logger.debug "instance_ids = #{instance_ids.inspect} number=#{(instance_ids == nil ? 0 : instance_ids.length)}"
    if instance_ids == nil || instance_ids.length == 0
      return transform_instances(@instances)
    else
      return transform_instances(@instances.select() {|i|
        instance_ids.include?(i[:instance_id])
      })
    end
  end

  def transform_instances(instances)
    @logger.debug "found #{instances.size} instances to transform"
    ret = {}
    ret['requestId'] = "request-id-dummy"
    ret['reservationSet'] = {}
    items = []
    ret['reservationSet']['item'] = items
    instances.each() {|i|
      @logger.debug "start transforming #{i.inspect}"
      item = {}
      groupSet = []
      instancesSet = {}
      #item['reservationId'] = "r-"+i[:instance_id]
      item['reservationId'] = "#{i[:image_id].gsub("ami", "r")}"
      item['ownerId'] = "owner-dummy-id"
      item['requesterId'] = 'dummy-requester-id'
      item['groupSet'] = {}
      item['groupSet']['item'] = groupSet
      item['instancesSet'] = instancesSet
      instancesSet['item'] = []
      instanceInfos = {}
      instancesSet['item'] << instanceInfos
      instanceInfos['keyName'] = i[:key_name]
      #instanceInfos['ramdiskId'] = 'dummy-ramdisk-id'
      instanceInfos['ramdiskId'] = "#{i[:image_id].gsub("ami", "ari")}"
      instanceInfos['productCodes'] = nil #TODO: must be a set
      #instanceInfos['kernelId'] = 'aki-'+i[:instance_id]
      instanceInfos['kernelId'] = "#{i[:image_id].gsub("ami", "aki")}"
      instanceInfos['launchTime'] = DateTime.new
      instanceInfos['amiLaunchIndex'] = 0 #TODO: count instances?
      instanceInfos['imageId'] = i[:image_id]
      instanceInfos['instanceType'] = "m1.small" #TODO: must be configurable
      instanceInfos['reason'] = nil #TODO: have a closer look at this
      instanceInfos['placement'] = {}
      instanceInfos['placement']['availabilityZone'] = i[:availability_zone]
      instanceInfos['instanceId'] = i[:instance_id]
      instanceInfos['privateDnsName'] = i[:private_dns_name]
      instanceInfos['dnsName'] = i[:dns_name]
      instanceInfos['instanceState'] = {}
      instanceInfos['instanceState']['name'] = i[:instance_state]
      instanceInfos['instanceState']['code'] = state_to_code(i[:instance_state])
      instanceInfos['architecture'] = "i386"
      instanceInfos['instanceType'] = "m1.small"
      instanceInfos['virtualizationType'] = "paravirtual"
      instanceInfos['rootDeviceName'] = "/dev/sda1"
      instanceInfos['rootDeviceType'] = "ebs"
      blockDeviceMapping = []
      instanceInfos['blockDeviceMapping'] = {}
      instanceInfos['blockDeviceMapping']['item'] = blockDeviceMapping
      tagSet = []
      instanceInfos['tagSet'] = {}
      instanceInfos['tagSet']['item'] = tagSet
      i[:tagSet].each() {|key_value|
        tagSet << {'key' => key_value[:key], 'value' => key_value[:value]}
      }
      i[:volumes].each() {|vol|
        elem = {}
        elem['ebs'] = {}
        elem['ebs']['volumeId'] = vol[:volume_id]
        elem['ebs']['status'] = "attached"
        elem['deviceName'] = "/dev/sda1"
        #TODO: more info
        blockDeviceMapping << elem
      }
      unless i[:groups] == nil
        @logger.debug "mocked_ec2_api is going to add #{i[:groups].size} groups" unless i[:groups] == nil
        i[:groups].each() {|group_name|
          sg = lookup_group(:group_name => group_name)
          if sg == nil
            next
            raise Exception.new("could not find group with name #{group_name}")
          end
          elem = {}
          elem['groupId'] = sg[:group_id]
          elem['groupName'] = sg[:group_name]
          groupSet << elem
        }
      else
        item['groupSet'] = nil
      end
      @logger.debug "going to add item = #{item.inspect}"
      items << item
    }
    return ret
  end

  def state_to_code(state)
    case state
    when "running"
      return 16
    when "pending"
      return 0
    when "terminated"
      return 48
    when "terminating"
      return 32
    when "stopped"
      return 80
    else
      return -1
    end

  end

  def get_instance(id)
    @instances.each() {|i|
      if i[:instance_id] == id
        @logger.debug "get_instance: #{i.inspect}"
        return i
      end
    }
    @logger.debug "no instance found"
    return nil
  end

  #result of describe_instances:
  #{"requestId"=>"9286df07-8937-4233-954a-e26b13780c2f", "reservationSet"=>{"item"=>[{"reservationId"=>"r-66d2260e", "requesterId"=>"058890971305", "groupSet"=>{"item"=>[{"groupId"=>"Rails Starter"}]}, "instancesSet"=>{"item"=>[{"keyName"=>"jungmats", "ramdiskId"=>"ari-dbc121b2", "productCodes"=>nil, "kernelId"=>"aki-f5c1219c", "launchTime"=>"2009-10-22T14:26:12.000Z", "amiLaunchIndex"=>"0", "imageId"=>"ami-22b0534b", "instanceType"=>"m1.small", "reason"=>nil, "placement"=>{"availabilityZone"=>"us-east-1d"}, "instanceId"=>"i-0071c968", "privateDnsName"=>"ip-10-244-159-112.ec2.internal", "dnsName"=>"ec2-174-129-149-1.compute-1.amazonaws.com", "instanceState"=>{"name"=>"running", "code"=>"16"}}]}, "ownerId"=>"945722764978"}, {"reservationId"=>"r-0e13e166", "requesterId"=>"058890971305", "groupSet"=>{"item"=>[{"groupId"=>"EU"}, {"groupId"=>"cloudkick"}]}, "instancesSet"=>{"item"=>[{"keyName"=>"jungmats", "ramdiskId"=>"ari-dbc121b2", "productCodes"=>nil, "kernelId"=>"aki-f5c1219c", "launchTime"=>"2009-10-27T18:05:03.000Z", "amiLaunchIndex"=>"0", "imageId"=>"ami-2cb05345", "instanceType"=>"m1.small", "reason"=>nil, "placement"=>{"availabilityZone"=>"us-east-1d"}, "instanceId"=>"i-16e8687e", "privateDnsName"=>"ip-10-245-206-177.ec2.internal", "dnsName"=>"ec2-67-202-11-96.compute-1.amazonaws.com", "instanceState"=>{"name"=>"running", "code"=>"16"}}]}, "ownerId"=>"945722764978"}]}, "xmlns"=>"http://ec2.amazonaws.com/doc/2008-12-01/"}


  def create_instance(instance_id, groups, tag_set = ['tag-set'])
    instance = {}
    instance[:instance_id] = instance_id
    #instance[:image_id] = "dummy image"
    instance[:image_id] = instance_id.gsub("i-", "ami-")
    instance[:volumes] = []
    instance[:tagSet] = tag_set
    instance[:instance_state] = "running"
    instance[:groups] = groups
    #TODO
    @instances << instance
    groups.each() {|group|
      unless @security_groups.include?(group)
        create_security_group({:group_name => group})
      end
    }
    #XXX: create at least one root volume associated to the instance
    volume = create_volume(:volume_id => instance_id.gsub("i-", "vol-"), :availability_zone => "us-east-1a")
    attach_volume(:instance_id => instance_id, :volume_id => volume[:volume_id], :device => "/dev/sda1")
    instance[:volumes] << volume
    instance
  end

  def create_dummy_instance(instance_id, image_id, instance_state, private_dns_name, dns_name, key_name, groups = [])
    instance = {}
    instance[:instance_id] = instance_id
    instance[:image_id] = image_id
    instance[:instance_state] = instance_state
    instance[:private_dns_name] = private_dns_name
    instance[:dns_name] = dns_name
    instance[:key_name] = key_name
    instance[:groups] = groups
    instance[:availability_zone] = "us-east-1a" #TODO: make configurable
    instance[:volumes] = []#
    instance[:tagSet] = ["dummy"]
    #
    #TODO
    @instances << instance
    unless groups == nil
      groups.each() {|group|
        unless @security_groups.include?(group)
          create_security_group({:group_name => group})
        end
      }
    end
    instance
  end

  def lookup_group(options)
    #either use group_name or group_id
    group_id = options[:group_id] || "XXXX"
    group_name = options[:group_name] || "XXXX"
    @security_groups.each() {|sg|
      return sg if sg[:group_name] == group_name || sg[:group_id] == group_id
    }
    nil
  end

  def terminate_instances(options)
    get_instance(options[:instance_id])[:instance_state] = "terminated"
  end

  def stop_instances(options)
    get_instance(options[:instance_id])[:instance_state] = "stopped"
  end

  def start_instances(options)
    get_instance(options[:instance_id])[:instance_state] = "running"
  end

  #private

  def cause_failure()
    if @fail
      @logger.debug "mocked_ec2 API is in failure mode"
      raise Exception.new("mocked_ec2 API is in failure mode")
    end
    if @provoke_authfailure
      @logger.debug "mocked_ec2 API to provode auth-failures"
      raise AWS::AuthFailure.new("mocked_ec2 API is in failure mode")
    end
  end

  def create_snapshot_old(volume_id)
    cause_failure()
    @logger.debug("MockedEc2API: create snapshot for #{volume_id}")
    #snap = "snap_#{Time.now.to_i.to_s}"
    puts "--- mock_ec2_api: create_snapshot #{volume_id}"
    snap = volume_id.gsub("vol","snap")
    s = {"volumeId"=>"#{volume_id}", "snapshotId"=>"#{snap}", "requestId"=>"dummy-request",
      "progress"=>"100%", "startTime"=>"2009-11-11T17:06:14.000Z", "volumeSize"=>"5",
      "status"=>"completed", "xmlns"=>"http://ec2.amazonaws.com/doc/2008-12-01/"}
    @snapshots << s
    s
  end

  def create_snapshot( options = {} )
    drop "--- mock_ec2_api: create_snapshot"
    volume_id = options[:volume_id]
    snap_id = volume_id.gsub("vol","snap")
    size = 5
    if options[:size] != nil
      size = options[:size]
    end
    snap = {"volumeId"=>"#{volume_id}", "snapshotId"=>"#{snap_id}", "requestId"=>"dummy-request",
      "progress"=>"100%", "startTime"=>"2009-11-11T17:06:14.000Z", "volumeSize"=>"#{size}",
      "status"=>"completed", "xmlns"=>"http://ec2.amazonaws.com/doc/2008-12-01/"}
    @snapshots << snap
    snap
  end

  def describe_snapshots(options = {})
    if options[:snapshot_id] == nil
      res = @snapshots
    else
      res = @snapshots.select() {|s|
        s['snapshotId'] == options[:snapshot_id]
      }
    end
    ret = {}
    ret['snapshotSet'] = {}
    ret['snapshotSet']['item'] = res
    ret
  end

  def delete_snapshot(options = {})
    res = {}
    res['return'] = "true"
    res['requestId'] = "dummy-request-id"
    res['xmlns'] = "http://ec2.amazonaws.com/doc/2008-12-01/"
    res
  end

  def describe_images_old(options = {})
    image_id = options[:image_id]
    if image_id == nil
      raise Exception.new("no image_id specified")
    end
    res = {"imagesSet"=>{"item"=>[{"imageType"=>"machine", "blockDeviceMapping"=>nil, "ramdiskId"=>"ari-a51cf9cc", "imageState"=>"available", "kernelId"=>"aki-a71cf9ce", "imageId"=>image_id, "rootDeviceType"=> @rootDeviceType, "isPublic"=>"true", "imageLocation"=>"jungmats_testbucket/openvpn.manifest.xml", "architecture"=>"i386", "imageOwnerId"=>"945722764978"}]}, "requestId"=>"625dd61b-53a5-4907-ab2a-a00a7dca05be", "xmlns"=>"http://ec2.amazonaws.com/doc/2009-11-30/"}
    res
  end

  def describe_keypairs(keynames = nil)
    cause_failure()
    all_key_names = []
    if keynames == nil
      keynames = []
      @instances.each() {|i|
        all_key_names << i[:key_name]
      }
    else
      keynames = keynames[:key_name]
      @instances.each() {|i|
        if i[:key_name] == keynames[0]
          all_key_names << i[:key_name]
        end
      }
    end
    res = {}
    res['keySet'] = {}
    res['keySet']['item'] = []
    res['keySet']['requestId'] = "dummy-request-id"
    res['keySet']['xmlns'] = "http://ec2.amazonaws.com/doc/2008-12-01/"
    all_key_names.each() {|kn|
      key = {}
      key['keyName'] = kn
      key['keyFingerprint'] = "00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99"
      res['keySet']['item'] << key
    }
    res
  end

  # Expects eiter an empty value or an hash {:volume_id => [bla]}
  def describe_volumes(volume_ids = nil)
    if volume_ids != nil
      #needed to adapt to the API
      volume_ids = [volume_ids[:volume_id]]
    else
      volume_ids = []
    end
    cause_failure()
    @logger.debug "describe_volumes: params = #{volume_ids.inspect} number=#{volume_ids.length}"
    if volume_ids.length == 0
      v = @volumes
    else
      v = @volumes.select() {|i|
        @logger.debug "compare '#{i[:volume_id].inspect}' with '#{volume_ids[0].inspect}' =>#{(i[:volume_id] == volume_ids[0])}"
        (i[:volume_id] == volume_ids[0])
      }
    end
    @logger.debug "all volumes = #{@volumes.inspect} v=#{v.inspect}"
    transform_volumes(v)
  end

  def create_volume(params)
    if params[:volume_id] != nil
      self.next_volume_id = params[:volume_id]
    end
    cause_failure()
    if params[:availability_zone] == nil || params[:availability_zone].strip.size == 0
      raise Exception.new("must specify availability zone")
    end
    @logger.debug "GOING TO CREATE VOLUME!"
    volume = {}
    vid = "vol-#{Time.now.to_i.to_s}"
    if next_volume_id() != nil
      vid = next_volume_id()
    end
    @next_volume_id = nil
    volume[:volume_id] = vid
    @logger.debug "create volume with id = #{volume[:volume_id]}"
    volume[:availability_zone] = params[:availability_zone]
    volume[:create_time] = params[:create_time] || Time.now.to_s
    #volume[:volume_id]
    if params[:size] != nil
      volume[:size] = params[:size] 
    else
      volume[:size] = 1
    end
    volume[:attachments] = []
    volume[:state] = "available"
    @volumes << volume
    transform_volumes([get_volume(vid)])['volumeSet']['item'][0]
  end

  def transform_volumes(volumes)
    @logger.debug "found #{volumes.size} volumes to transform"
    ret = {}
    ret['volumeSet'] = {}
    items = []
    ret['volumeSet']['item'] = items
    volumes.each() {|v|
      @logger.debug "start transforming #{v.inspect}"
      item = {}
      attachmentSet = {}
      item['attachmentSet'] = attachmentSet #TODO: attachments not yet possible
      if v[:attachments].size > 0
        @logger.debug "#{item['attachmentSet']}"
        item['attachmentSet']['item'] = []
        v[:attachments].each() {|a|
          @logger.debug "attachment found: #{a.inspect}"
          attachments = {}
          attachments['device'] = a[:device]
          attachments['volumeId'] = v[:volume_id]
          attachments['instanceId'] = a[:instance_id]
          attachments['status'] = "attached"
          attachments['attachTime'] = DateTime.now
          item['attachmentSet']['item'] << attachments
        }
      end
      item['createTime'] = v[:create_time]
      #item['size'] = 1 #TODO make configurable?
      if v[:size] != nil
        item['size'] = v[:size]
      else
        item['size'] = 1
      end
      item['volumeId'] = v[:volume_id]
      item['snapshotId'] = nil #TODO: make configurable?
      item['status'] = v[:state]
      item['availabilityZone'] = v[:availability_zone]
      items << item
    }
    return ret
  end

  def attach_volume(options)
    cause_failure()
    volume_id = options[:volume_id]
    instance_id = options[:instance_id]
    device = options[:device]
    @logger.debug "attach vol #{volume_id} to instance #{instance_id}"
    volume = get_volume(volume_id)
    @logger.debug "volume = #{volume.inspect}"
    instance = get_instance(instance_id)
    @logger.debug "instance = #{instance.inspect}"
    if volume == nil
      raise Exception.new("volume #{volume_id} does not exist")
    end
    if instance == nil
      raise Exception.new("instance #{instance_id} does not exist")
    end
    att = {}
    att[:instance_id] = instance_id
    att[:device] = device
    @logger.debug "add #{att.inspect} to attachments = #{volume[:attachments].inspect}"
    update_volume_state(volume_id, "in-use")
    volume[:attachments] << att
    instance[:volumes] << volume
    @logger.debug "after attaching: #{@volumes.inspect}"
  end

  def detach_volume(options)
    cause_failure()
    volume = get_volume(options[:volume_id])
    @logger.debug "volume = #{volume.inspect}"
    instance = get_instance(options[:instance_id])
    @logger.debug "instance = #{instance.inspect}"
    if volume == nil
      raise Exception.new("volume #{options[:volume_id]} does not exist")
    end
    if instance == nil
      raise Exception.new("instance #{options[:instance_id]} does not exist")
    end
    att = volume[:attachments]
    @logger.debug "attachments = #{att.inspect}"
    count = 0
    to_remove = -1
    att.each() {|a|
      if a[:instance_id] == options[:instance_id]
        @logger.debug "going to remove #{a.inspect}"
        to_remove = count
        break
      end
      count += 1
    }
    if to_remove != -1
      volume[:attachments].delete_at(to_remove)
    end
    update_volume_state(options[:volume_id], "available")
    #remove from instance
    instance[:volumes].delete_if() {|vol|
      drop "delete volum #{vol.inspect} from instance #{instance.inspect}?"
      vol[:volume_id] == options[:volume_id]
    }
    @logger.debug "after detaching: #{@volumes.inspect}"
  end

  def delete_volume(options)
    volume_id = options[:volume_id]
    remove_dummy_volume(volume_id)
  end

  #the following methods are additional helper methods

  def create_dummy_volume(id, timezone)
    self.next_volume_id = id
    return create_volume({:availability_zone => timezone})
  end

  def remove_dummy_volume(id)
    @volumes = @volumes.select() {|v|
      v[:volume_id] != id
    }
  end

  def get_volume(id)
    @volumes.each() {|v|
      if v[:volume_id] == id
        @logger.debug "get_volume: #{v.inspect}"
        return v
      end
    }
    @logger.debug "no volume found"
    return nil
  end

  def change_group_id(group_id, value)
    sg = lookup_group({:group_id => group_id})
    drop "-- mock_ec2_api: change_group_id to #{value} for #{sg.inspect}"
    sg[:group_id] = value
  end

  def update_volume_state(volume_id, state)
    @logger.debug "update_volume_state for #{volume_id} to #{state}"
    v = get_volume(volume_id)
    v[:state] = state
  end

  def register_image_updated(options)
    @logger.debug "register_image for #{options[:snapshot_id]} name #{options[:name]}"
    {'imageId' => "ami-#{options[:snapshot_id]}"}
  end

  #VPC support
  def create_vpc( options = {} )
    drop "-- mock_ec2_api: create_vpc"
    @vpcs << {:vpc_id => options[:vpc_id], :cidr_blk => options[:cidr_blk]}
  end

  def describe_vpcs( options = {} )
    drop "-- mock_ec2_api: describe_vpc"
    vpcs = @vpcs
    ret = {}
    ret['vpcSet'] = {}
    items = []
    ret['vpcSet']['item'] = items
    vpcs.each() {|vpc|
      item = {}
      item['dhcpOptionsId'] = "dopt-12345678"
      item['instanceTenancy'] = "default"
      item['cidrBlock'] = "#{vpc[:cidr_blk]}"
      item['vpcId'] = "#{vpc[:vpc_id]}"
      item['state'] = "available"
      items << item
    }
    return ret
  end

  def create_internetgateway( options = {} )
    drop "-- mock_ec2_api: create_internetgateway"
    @igws << {:igw_id => options[:igw_id], :vpc_id => options[:vpc_id]}
  end

  def describe_internetgateways( options = {} )
    drop "-- mock_ec2_api: describe_internetgateways"
    igws = @igws
    ret = {}
    ret['internetGatewaySet'] = {}
    items = []
    ret['internetGatewaySet']['item'] = items
    igws.each() {|igw|
      item = {}
      attachmentSet = {}
      item['attachmentSet'] = attachmentSet
      item['attachmentSet']['item'] = []
      attachments = {}
      attachments['vpcId'] = "#{igw[:vpc_id]}"
      attachments['state'] = "available"
      item['attachmentSet']['item'] << attachments
      item['tagSet'] = nil
      item['internetGatewayId'] = "#{igw[:igw_id]}" 
      items << item
    }
    return ret
  end

  def create_image( options = {} )
    drop "--- mock_ec2_api: create_image"
    ami = {}
    ami[:ami_id] = "ami-from-#{options [:instance_id]}"
    ami[:name] = options[:name]
    ami[:desc] = options [:desc]
    instanceset = describe_instances(:instance_id => options [:instance_id])
    instance_info = instanceset['reservationSet']['item'][0]['instancesSet']['item'][0]
    ami[:root_device_name] = instance_info['rootDeviceName']
    ami[:root_device_type] = instance_info['rootDeviceType']
    ami[:arch] = instance_info['architecture'] 
    @images << ami
    images = describe_images(:image_id => ami[:ami_id])
    images['imagesSet']['item'][0]
  end

  def create_dummy_image( options = {} )
    drop "--- mock_ec2_api: create_dummy_image"
    ami = {}
    ami[:ami_id] = options[:ami_id]
    ami[:name] = options[:name]
    ami[:desc] = options [:desc]
    ami[:root_device_name] = options[:root_device_name]
    ami[:root_device_type] = options[:root_device_type]
    ami[:platform] = options[:platform]
    ami[:arch] = options[:arch]
    @images << ami
    ami
  end

  def describe_images( options = {} )
    drop "--- mock_ec2_api: describe_images"
    images = @images
    if options[:image_id] != nil
      images = images.select() {|ami|
        ami[:ami_id] == options[:image_id]
      }
    end
    res = transform_images(images)
    res
  end

  def transform_images( images )
    ret = {}
    ret['requestId'] = "request-id-dummy"
    ret['imagesSet'] = {}
    items = []
    ret['imagesSet']['item'] = items
    images.each() {|ami|
      @logger.debug "start transforming #{ami.inspect}"
      item = {}
      item['name'] = "#{ami[:name]}"
      item['imageType'] = "machine"
      item['blockDeviceMapping'] = {}
      item['blockDeviceMapping']['item'] = []
      blkdevmap = {}
      blkdevmap['ebs'] = {}
      ebs = {}
      ebs['snapshotId'] = "#{ami[:ami_id].gsub("ami", "snap")}"
      ebs['deleteOnTermination'] = "true"
      ebs['volumeSize'] = "20"
      blkdevmap['deviceName'] = "/dev/sda1"
      blkdevmap['ebs'] = ebs
      item['blockDeviceMapping']['item'] << blkdevmap
      item['imageState'] = "available"
      item['imageId'] = ami[:ami_id]
      item['rootDeviceName'] = ami[:root_device_name]
      item['rootDeviceType'] = ami[:root_device_type]
      item['description'] = ami[:desc]
      item['imageOwnerAlias'] = "someone"
      item['isPublic'] = "true"
      item['imageLocation'] = "somewhere"
      if ami[:platform].eql?("windows")
        item['virtualizationType'] = "hvm"
      else
        item['virtualizationType'] = "paravirtual"
      end
      item['platform'] = ami[:platform]
      item['architecture'] = ami[:arch]
      item['imageOwnerId'] = "123412341234"
      items << item
    }
    return ret
  end

#    res = {"imagesSet"=>{"item"=>[{"imageType"=>"machine", "blockDeviceMapping"=>nil, "ramdiskId"=>"ari-a51cf9cc", "imageState"=>"available", "kernelId"=>"aki-a71cf9ce", "imageId"=>image_id, "rootDeviceType"=> @rootDeviceType, "isPublic"=>"true", "imageLocation"=>"jungmats_testbucket/openvpn.manifest.xml", "architecture"=>"i386", "imageOwnerId"=>"945722764978"}]}, "requestId"=>"625dd61b-53a5-4907-ab2a-a00a7dca05be", "xmlns"=>"http://ec2.amazonaws.com/doc/2009-11-30/"}

  def local_dump_and_compress(source_device, target_filename)
    drop "--- mock_ec2_api: local_dump_and_compress"
  end

  def local_decompress_and_dump(source_filename, target_device)
    drop "--- mock_ec2_api: local_decompress_and_dump"
  end

end
