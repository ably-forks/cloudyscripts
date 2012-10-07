require 'AWS'

class EC2_Utils
	attr_reader :ec2

	public
	def initialize(ec2_options)
		@ec2 = AWS::EC2::Base.new(ec2_options)
	end
	# Get public DNS name of an instance.
	# If the instance is not yet started and the DNS name not known, block until the instance is started.
	#
	# @param instance_id Instance ID of the instance that you want to get the DNS from.
	# @param ec2 The AWS::EC2::Base object that is used to access EC2.
	# @return Public DNS name of the instance as String.
	public
	def get_instance_public_dns(instance_id)
		error_count = 0
		begin
			while (true) do
				instances = @ec2.describe_instances(:instance_id => instance_id)
				# protect against nil errors because parts of the structure are not initialized when the DNS is not known
				begin
					dns_name = instances["reservationSet"]["item"][0]["instancesSet"]["item"][0]["dnsName"]
					return dns_name if dns_name
				rescue => err
				end
				sleep(5)
			end
		rescue => err
			error_count += 1
			raise err if error_count > 3

			sleep(5)
			retry
		end
	end

	# Get the AMI from a started instance.
	#
	# @param instance_id The instance id that the machine id is retrieved for.
	# @param ec2 The AWS::EC2::Base object that is used to access EC2.
	# @return Machine id of the instance as String.
	public
	def get_image_id(instance_id)
		instances = @ec2.describe_instances(:instance_id => instance_id)
		if instances then
			return instances["reservationSet"]["item"][0]["instancesSet"]["item"][0]["imageId"]
		else
			return "none"
		end
	end

	public
	def get_instance_states()
		instanceStates = []
		@ec2.describe_instances()['reservationSet']['item'].each do|x|
			x['instancesSet']['item'].each do|y|
				instanceStates << {:instance_id => y['instanceId'],
				                   :state => y['instanceState']['name'],
				                   :image_id => y['imageId'],
				                   :runtime => (DateTime.now() - DateTime.strptime(y['launchTime'], "%Y-%m-%dT%H:%M:%S")) * 24.0}
			end
		end
		return instanceStates
	end

	public
	def get_cheapest_instance_type(machine_id)
		machines = @ec2.describe_images(:image_id => machine_id)
		begin
			return "t1.micro" if machines['imagesSet']['item'][0]['rootDeviceType'] == "ebs"
			return 'm1.small' if machines['imagesSet']['item'][0]['architecture'] == "i386"
			return "m1.small" if machines['imagesSet']['item'][0]['architecture'] == "x86_64"
		rescue => err
		end

		puts "ERROR: Finding cheapest instance type in EC2_Utils::get_cheapest_instance_type for machine_id = #{machine_id}"
		return "t1.micro"
	end

	public
	def start_instance(options)
		raise "Invalid parameters to EC2_Utils::start_instance: :id is missing" unless options[:id]

		if /^ami-.*$/.match(options[:id]) then
			raise "Invalid parameters to EC2_Utils::start_instance: :ssh_keypair is missing" unless options[:ssh_keypair]
			raise "Invalid parameters to EC2_Utils::start_instance: :instance_type is missing" unless options[:instance_type]
			raise "Invalid parameters to EC2_Utils::start_instance: :security_group is missing" unless options[:security_group]

			instance_id = false
			if options[:max_price] then
				spot_request = @ec2.request_spot_instances(
					:image_id => options[:id],
					:instance_count => 1,
					:key_name => options[:ssh_keypair],
					:security_group => options[:security_group],
					:disable_api_termination => false,
					:instance_type => options[:instance_type],
					:spot_price => options[:max_price],
					:valid_from => nil,
					:valid_until => nil)

				spot_request_id = spot_request['spotInstanceRequestSet']['item'][0]['spotInstanceRequestId']
				begin
					spot_reqs = ec2.describe_spot_instance_requests()
					spot_req = spot_reqs['spotInstanceRequestSet']['item'].reject{|x| x['spotInstanceRequestId'] != spot_request_id}

					raise "Spot request #{spot_request_id} seems to have disappeared" if spot_req.length() != 1

					if spot_req[0]['instanceId'] then
						instance_id = spot_req[0]['instanceId']
					end

					sleep(30)
				end until instance_id
			else
				instance = @ec2.run_instances(
					:image_id => options[:id],
					:max_count => 1,
					:key_name => options[:ssh_keypair],
					:security_group => options[:security_group],
					:disable_api_termination => false,
					:instance_type => options[:instance_type])
				instance_id = instance["instancesSet"]["item"][0]["instanceId"]
			end

			image_id = options[:id]
		elsif /^i-.*$/.match(options[:id]) then
			instance_id = options[:id]
			image_id = get_image_id(instance_id)
		else
			raise "Unknown identifier #{options[:id]}"
		end

		puts "instance #{instance_id} started, waiting for IP address" if options[:verbose]
		begin
			dns_name = get_instance_public_dns(instance_id)
		rescue => err
			puts "ERROR: During DNS request of AMI" if options[:verbose]
		end

		if dns_name.nil? || dns_name.empty? then
			puts "ERROR: No DNS name for AMI found" if options[:verbose]
			raise "No DNS name for AMI found"
		end

		return {:machine_id => image_id,
		        :instance_id => instance_id,
		        :public_dns => dns_name}
	end

	public
	def get_instance_volumes(instance_id)
		volumes = []
		instances = @ec2.describe_instances(:instance_id => [instance_id])

		instances['reservationSet']['item'].each do|reservationSet|
			next unless reservationSet['instancesSet']

			reservationSet['instancesSet']['item'].each do|instancesSet|
				next unless instancesSet['blockDeviceMapping']

				instancesSet['blockDeviceMapping']['item'].each do|blockDeviceMapping|
					next unless blockDeviceMapping['ebs']

					volumes << blockDeviceMapping['ebs']['volumeId']
				end
			end
		end

		return volumes
	end

	public
	def terminate_instance(instance_id)
		volumes = get_instance_volumes(instance_id)

		@ec2.terminate_instances(:instance_id => [instance_id])

		begin
			#wait till instance is terminated
			begin
				instance_state = @ec2.describe_instances(:instance_id => [instance_id])['reservationSet']['item'][0]['instancesSet']['item'][0]['instanceState']['name']
			end unless instance_state == "terminated"

			#delete volumes
			volumes.each do|volume|
				begin
					@ec2.detach_volumes(:volume_id => volume)
				rescue => err
				end

				@ec2.delete_volume(:volume_id => volume)
			end
		rescue => err
			if err.class() == AWS::Error  && /The volume 'vol-[0-9a-f]{8}' does not exist/.match(err.message()) then
				#ignore error
			end
		end
	end

	public
	def get_spot_prices(options = {})
		arg = {:start_time => Time.now() - 1, :end_time => Time.now()}
		arg[:instance_type] = options[:instance_type] if options[:instance_type]
		spot_prices = ec2.describe_spot_price_history(arg)

		prices = {}
		if spot_prices["spotPriceHistorySet"] then
			spot_prices["spotPriceHistorySet"]["item"].each do|spot_price|
				(prices[spot_price["instanceType"]] ||= {})[spot_price["productDescription"]] = {:price => spot_price["spotPrice"], :timestamp => spot_price["timestamp"]}
			end
		end

		return prices
	end
end

# taken from https://github.com/grempe/amazon-ec2/blob/master/lib/AWS/EC2/console.rb ------------------------->
module AWS
  module EC2
    class Base < AWS::Base


      # The GetConsoleOutput operation retrieves console output that has been posted for the specified instance.
      #
      # Instance console output is buffered and posted shortly after instance boot, reboot and once the instance
      # is terminated. Only the most recent 64 KB of posted output is available. Console output is available for
      # at least 1 hour after the most recent post.
      #
      # @option options [String] :instance_id ("") an Instance ID
      #
      def get_console_output( options = {} )
        options = {:instance_id => ""}.merge(options)
        raise ArgumentError, "No instance ID provided" if options[:instance_id].nil? || options[:instance_id].empty?
        params = { "InstanceId" => options[:instance_id] }
        return response_generator(:action => "GetConsoleOutput", :params => params)
      end


    end
  end
end
# <----------------------------------------------------------------------------------------------------------
