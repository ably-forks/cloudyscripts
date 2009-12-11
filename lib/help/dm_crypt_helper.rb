require 'lib/ssh_api'

class DmCryptHelper

  def set_ssh(ssh_session)
    @ssh_session = ssh_session
  end

  def install()
    #TODO: dm-crypt seems to be installed automatically
    true
  end

  def tools_installed?()
    @ssh_session.exec! "which dmsetup" do |ch, stream, data|
      if stream == :stderr
        return false
      end
    end
    @ssh_session.exec! "which cryptsetup" do |ch, stream, data|
      if stream == :stderr
        return false
      end
    end
    #TODO: check also that "/dev/mapper /dev/mapper/control" exist
    true
  end

  def encrypt_storage(name, password, device, path)
    # first: check if a file in /dev/mapper exists
    if SshApi.file_exists?(@ssh_session, "/dev/mapper/dm-#{name}")
      mapper_exists = true
    else
      mapper_exists = false
    end
    puts "mapper exists = #{mapper_exists}"
    exec_string = "cryptsetup create dm-#{name} #{device}"
    if !mapper_exists
      #mapper does not exist, create it
      channel = @ssh_session.open_channel do |ch|
        ch.send_data("#{password}\n")
        puts "execute #{exec_string}"
        ch.exec exec_string do |ch, success|
          puts "success = #{success}"
          if !success
            err = "Failed during creation of encrypted partition"
            #puts "#{err}: #{data}"
            raise Exception.new(err)
          end
        end
      end
      channel.wait
    end
    # now mapper is created
    # second: check if pvscan sucessful
    pv_exists = false
    @ssh_session.exec! "/sbin/pvscan" do |ch, stream, data|
      if stream == :stdout
        if data.include?("vg-#{name}")
          pv_exists = true
        else
          pv_exists = false
        end
      end
    end
    if !pv_exists
      exec_string = "pvcreate /dev/mapper/dm-#{name}"
      puts "pv does not exist - execute: #{exec_string}"
      #private volume does not exist, create it
      channel = @ssh_session.open_channel do |ch|
        ch.send_data("y\n")
        ch.exec exec_string do |ch, success|
          puts "success = #{success}"
          if !success
            err = "Failed during creation of physical volume"
            #puts "#{err}: #{data}"
            raise Exception.new(err)
          end
        end
      end
      channel.wait
    end
    # third: check if vgscan successful
    vg_exists = false
    @ssh_session.exec! "/sbin/vgscan" do |ch, stream, data|
      if stream == :stdout
        if data.include?("vg-#{name}")
          vg_exists = true
        else
          vg_exists = false
        end
      end
    end
    if !vg_exists
      exec_string = "vgcreate vg-#{name} /dev/mapper/dm-#{name}"
      puts "vg_exists == false; execute #{exec_string}"
      @ssh_session.exec! exec_string do |ch, stream, data|
        if stream == :stderr && !data.blank?
          err = "Failed during creation of volume group"
          puts "#{err}: #{data}"
          raise Exception.new(err)
        end
      end
      #exec_string = "lvcreate -n lv-#{name} -L#{size_in_mb.to_s}M vg-#{name}"
      exec_string = "lvcreate -n lv-#{name} -l100%FREE vg-#{name}"
      puts "execute #{exec_string}"
      @ssh_session.exec! exec_string do |ch, stream, data|
        if stream == :stderr && !data.blank?
          err = "Failed during creation of logical volume"
          puts "#{err}: #{data}"
          raise Exception.new(err)
        end
      end
      exec_string = "mkfs -t ext3 /dev/vg-#{name}/lv-#{name}"
      puts "execute #{exec_string}"
      @ssh_session.exec! exec_string #do |ch, stream, data|
        #if stream == :stderr && !data.blank?
        #err = "Failed during creation of file-system"
        #puts "#{err}: #{data}"
        #raise Exception.new(err)
        #end
      #end
      if !SshApi.file_exists?(@ssh_session,"/dev/vg-#{name}/lv-#{name}")
        err = "Missing file: /dev/vg-#{name}/lv-#{name}"
        raise Exception.new(err)
      end
    else
      exec_string = "/sbin/vgchange -a y vg-#{name}"
      puts "vg_exists == true; execute #{exec_string}"
      @ssh_session.exec! exec_string do |ch, stream, data| #TODO: the right size instead L2G!
        if stream == :stderr && !data.blank?
          err = "Failed during re-activation of volume group"
          puts "#{err}: #{data}"
          raise Exception.new(err)
        end
      end
    end
  end

  def test_storage_encryption(password, mount_point, path)
    raise Exception.new("not yet implemented")
  end

  def undo_encryption(name, path)
    exec_string = "umount #{path}"
    puts "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      puts "returns #{data}"
    end
    exec_string = "lvremove --verbose vg-#{name} -f" #[with confirmation?]
    puts "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      puts "returns #{data}"
    end
    exec_string = "vgremove vg-#{name}"
    puts "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      puts "returns #{data}"
    end
    exec_string = "pvremove /dev/mapper/dm-#{name}"
    puts "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      puts "returns #{data}"
    end
    exec_string = "cryptsetup remove dm-#{name}"
    puts "going to execute #{exec_string}"
    @ssh_session.exec! exec_string do |ch, stream, data|
      puts "returns #{data}"
    end
  end

end
