require "help/script_execution_state"
require "scripts/ec2/ec2_script"
require "help/remote_command_handler"
#require "help/dm_crypt_helper"
require "help/ec2_helper"
require "AWS"

# Identifies a number of resources that can be deleted:
# - duplicate snapshots for a given volume exceeding a certain threshold
# - unattached volumes created more than 1 day ago

class SnapshotOptimization < Ec2Script
  # Input parameters
  # * ec2_api_handler => object that allows to access the EC2 API
  def initialize(input_params)
    super(input_params)
  end

  def check_input_parameters()
    if @input_params[:ec2_api_handler] == nil
      raise Exception.new("no EC2 handler specified")
    end
    if @input_params[:delete_snapshots] == nil
      @input_params[:delete_snapshots] = false
    end
    if @input_params[:delete_volumes] == nil
      @input_params[:delete_volumes] = false
    end
    if @input_params[:max_duplicate_snapshots] == nil
      @input_params[:max_duplicate_snapshots] = 5
    end
  end

  def load_initial_state()
    SnapshotOptimizationState.load_state(@input_params)
  end

  private

  # Here begins the state machine implementation
  class SnapshotOptimizationState < ScriptExecutionState
    def self.load_state(context)
      state = context[:initial_state] == nil ? RetrieveSnapshots.new(context) : context[:initial_state]
      state
    end

  end

  # Nothing done yet. Retrieve all snapshots
  class RetrieveSnapshots < SnapshotOptimizationState
    def enter
      @context[:result][:duplicate_snapshots] = []
      @context[:result][:orphan_volumes] = []
      #
      @context[:snapshots] = ec2_handler().describe_snapshots(:owner => "self")
      puts "snapshots = #{@context[:snapshots].inspect}"
      IdentifyDuplicateSnapshots.new(@context)
    end
  end

  # All snapshots retrieved. Group them by volume and identify duplicates
  class IdentifyDuplicateSnapshots < SnapshotOptimizationState
    def enter
      volume_map = {}
      @context[:snapshots]['snapshotSet']['item'].each() do |snapshot|
        next unless snapshot['progress'] == "100%"
        puts "snapshot['ownerAlias'] = #{snapshot['ownerAlias']} for #{snapshot['snapshotId']}"
        next if snapshot['ownerAlias'] == "amazon"
        snaps = volume_map[snapshot['volumeId']]
        if snaps == nil
          snaps = []
          volume_map[snapshot['volumeId']] = snaps
        end
        snaps << snapshot
      end
      #
      volume_map.each() do |volume_id, snapshots|
        to_delete = snapshots.size - @context[:max_duplicate_snapshots]
        if to_delete <= 0
          post_message("Number of snapshots for volume #{volume_id} (=#{snapshots.size}) is smaller than #{@context[:max_duplicate_snapshots]} => ignore")
        else
          sorted_snaps = snapshots.sort() do |snap1, snap2|
            Time.parse(snap1['startTime']) <=> Time.parse(snap2['startTime'])
          end
          post_message("Identified #{to_delete} snapshots for volume #{volume_id}")
          @logger.info("not sorted   = #{snapshots.inspect}")
          @logger.info("sorted snaps = #{sorted_snaps.inspect}")
          0.upto(to_delete-1) do |i|
            @context[:result][:duplicate_snapshots] << sorted_snaps[i]['snapshotId']
          end
        end
      end
      if @context[:delete_snapshots]
        DeleteDuplicateSnapshots.new(@context)
      else
        RetrieveVolumes.new(@context)
      end
    end
  end

  # Duplicate snapshots identified. Retrieve volumes.
  class DeleteDuplicateSnapshots < SnapshotOptimizationState
    def enter
      post_message("Going to delete #{@context[:result][:duplicate_snapshots].size} snapshots")
      @context[:result][:duplicate_snapshots].each() do |snapshot_id|
        post_message("Going to delete snapshot #{snapshot_id}")        
        ec2_handler().delete_snapshot(:snapshot_id => snapshot_id)
      end
      RetrieveVolumes.new(@context)
    end
  end

  # Duplicate snapshots deleted. Retrieve volumes.
  class RetrieveVolumes < SnapshotOptimizationState
    def enter
      @context[:volumes] = ec2_handler().describe_volumes()
      IdentifyOrphanVolumes.new(@context)
    end
  end

  # Volumes retrieved. Identify unattached volumes that are older than a day
  class IdentifyOrphanVolumes < SnapshotOptimizationState
    def enter
      @logger.info("all volumes => #{@context[:volumes].inspect}")
      @context[:volumes]['volumeSet']['item'].each() do |volume|
        if volume['status'] == "available"
          age = Time.now.to_i - Time.parse(volume['createTime']).to_i
          @logger.info("age of orphan #{volume['volumeId']}: #{age/(60*60*24).to_f} days")
          if age < 60*60*24
            post_message("Volume #{volume['volumeId']} is unattached, but created within the last 24h => ignore")
          else
            post_message("Identified unattached volume #{volume['volumeId']}")
            @context[:result][:orphan_volumes] << volume['volumeId']
          end
          @logger.info("complete info on volume: #{volume.inspect}")
        else
          post_message("Volume #{volume['volumeId']} is attached => ignore")
        end
      end
      if @context[:delete_volumes]
        DeleteUnattachedVolumes.new(@context)
      else
        Done.new(@context)
      end
    end
  end

  # Nothing done yet. Retrieve all security groups
  class DeleteUnattachedVolumes < SnapshotOptimizationState
    def enter
      post_message("Going to delete #{@context[:result][:orphan_volumes].size} volumes")
      @context[:result][:orphan_volumes].each() do |volume_id|
        post_message("Going to delete volume #{volume_id}")
        ec2_handler().delete_volume(:volume_id => volume_id)
      end
      Done.new(@context)
    end
  end

  # Script done.
  class Done < SnapshotOptimizationState
    def done?
      true
    end
  end

end
