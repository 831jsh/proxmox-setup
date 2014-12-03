# http://nakkaya.com/2012/08/30/create-manage-virtualBox-vms-from-the-command-line/
# https://www.virtualbox.org/manual/ch08.html

# Other things you might want
# VBoxManage setproperty --hwvirtex on

def make_proxmox_vm(vm)
  # * Disk: Use a SSD if possible. Preallocated might provide faster access.
  hd_file=@disk_folder+"/#{vm}-HD.vdi"
  hd_on_ssd="on"
  hd_size_mb="20000" # 10,000 = 10GB
  ram_mb="3072"

  unless(File.file?(@install_iso))
    raise "ERROR - you need to download the ISO file at #{@install_iso} from https://www.proxmox.com/downloads"
  end

  ide_storage_name="IDE Controller for #{vm}"
  description = "Proxmox-in-Virtualbox generated by https://github.com/mrjcleaver/proxmox-in-virtualbox \n" + \
                    "Generated "+Time.now.to_s+ " using "+@install_iso

  run_shell_cmd("VBoxManage createvm --name '#{vm}' --register")
  run_shell_cmd("VBoxManage modifyvm '#{vm}' --description '#{description}'")
  # Note: Enabling the I/O APIC is required for 64-bit guest operating systems (page 48, manual)
  run_shell_cmd("VBoxManage modifyvm '#{vm}' --memory '#{ram_mb}' --acpi on --ioapic on --boot1 dvd --vram 12")

  run_shell_cmd("VBoxManage modifyvm '#{vm}' --ostype Debian --audio none")

  run_shell_cmd("VBoxManage createhd --filename '#{hd_file}' --size '#{hd_size_mb}' --variant Fixed")
  run_shell_cmd("VBoxManage storagectl '#{vm}' --name '#{ide_storage_name}' --add ide")

  run_shell_cmd("VBoxManage storageattach '#{vm}' --storagectl '#{ide_storage_name}' --port 0 --device 0 --type hdd --medium '#{hd_file}' --nonrotational=#{hd_on_ssd}")

  run_shell_cmd("VBoxManage storageattach '#{vm}' --storagectl '#{ide_storage_name}' --port 1 --device 0 --type dvddrive --medium '#{@install_iso}'")

  run_shell_cmd("VBoxManage setextradata '#{vm}' GUI/MouseCapturePolicy Default")
end

def start_proxmox_vm(vm)
  run_shell_cmd("VBoxManage startvm '#{vm}' ")
end





  hostonly_network="vmnet1" # user needs to make sure this is not served by DHCP
  # TODO: implement make_new_hostonly

  def download_or_use_iso(iso_name)
    # TODO
  end


  # NOTE: wlan bridging is not reliable, but
  def make_single_bridged_node(vm)
    make_proxmox_vm(vm)
    make_vbox_nic_connect_to_bridge(vm, @wifi_bridge)
  end

  def make_single_network_stable_node_NOT_IMPLEMENTED(vm)
    make_proxmox_vm(vm)
    #boot the vm - this will give the node its primary address from the default dhcp, i.e probably from wifi

    # vbox host setup

    define_vbox_subnet_for_nat(vm, @nat_net_cidr)

    #nat_net_cidr_cidr ** Adapter 1: NAT (attention: '''NOT''' NAT-network!!)
    connect_vbox_adapter(vm, 1, 'nat', @nat_net_cidr)


    #** Adapter 2: Host-only Adapter, vboxnet0; recommended leave the advanced settings as they are.
    make_vbox_host_only_network(name, @hostonly_network_ip)
    connect_to_hostonly(vm, @hostonly_network_ip)


    route_host_to_containers(@container_network_cidr, @hostonly_gateway)

    # proxmox in vbox setup

    # http://forum.proxmox.com/threads/20054-Proxmox-under-Virtualbox-no-outbound-networking
    #- vbox Proxmox virtual machine:
    #-- eth0 = "Adapter 1" connected with NAT - address 192.168.11.15/24, gateway 192.168.11.2, DNS 192.168.11.3
    #-- eth1 = "Adapter 2" connected with "Host only" - address 192.168.4.2/24
    #-- vmbr1 (not bridged to any NIC in virtual Proxmox host) - address 192.168.9.1/24

    nat_net_proxmox_ip = '192.168.11.15'  # not a global variable because in cluster we'd need a ip for each proxmox node
    nat_net_subnet_mask = '255.255.255.0'
    #-- eth0 = "Adapter 1" connected with NAT - address nat_net_proxmox_ip, gateway @nat_net_gateway, DNS @nat_net_dns
    #-- eth1 = "Adapter 2" connected with "Host only" - address @hostonly_gateway
    #-- vmbr1 (not bridged to any NIC in virtual Proxmox host) - address 192.168.9.1/24

    proxmox_ssh(vm, "pvesh set nodes/localhost/network/eth0 -type eth -address #{nat_net_proxmox_ip} -netmask #{nat_net_subnet_mask}")
    proxmox_ssh(vm, "pvesh set nodes/localhost/network/eth0 -gateway #{@nat_net_gateway}")

    proxmox_ssh(vm, "pvesh set nodes/localhost/network/eth1 -gateway #{@hostonly_gateway}")
    proxmox_ssh(vm, "pvesh set nodes/localhost/network/vmbr0 -address #{@container_network_vmbr_ip} -comments 'container network'")

    connect_to_private_network(vm, @nat_net_cidr)
  end


  # e.g. for a proxmox cluster
  #def make_pair_network_stable_nodes vm1, vm2
  #  make_proxmox_vm(vm1)
  #  make_proxmox_vm(vm2)
  #  connect_to_private_and_hostonlynetwork (vm, nat_net_cidr, hostonly_network)
  #end

  def connect_vbox_adapter(vm, adapter, type, address)
      run_shell_cmd("VBoxManage modifyvm '#{vm}' --nictype1 virtio --nic1 #{type} --bridgeadapter1 '#{adapter}'")
  end

  def make_vbox_nic_connect_to_bridge(vm, bridge_adapter)
      run_shell_cmd("VBoxManage modifyvm '#{vm}' --nictype1 virtio --nic1 bridged --bridgeadapter1 '#{bridge_adapter}'")
  end

  def inside_proxmox_make_virtual_bridge
    #Assuming the NIC connected to "NAT" is eth0.
    #* Make a bridge called vmbr1
    #* Bridge eth0 to it
    #* Assign an address from the NAT subnet to it, e.g. 192.168.11.15
    #* Set default gateway to "2" in the NAT subnet, e.g. 192.168.11.2

  end

  # === Access to Internet ===
  #
  # For accessing the internet use NAT - an address would be assigned by VirtualBox's DHCP service, usually something
  # like 10.0.2.15 - But to have it under control you should not use DHCP but set the IP address in PVE manually
  # and define the subnet manually too.

  # Set Adapter 1 to "NAT"
  def define_vbox_subnet_for_nat(vm, natnet)
      run_shell_cmd("VBoxManage modifyvm '#{vm} --natnet1 '#{natnet}'")
  end

  #== Create Host-Only Network in Virtualbox==
  #
  #This network is to permit traffic from the laptop to the Virtualbox.
  #
  # In Virtualbox, there may be a Host-Only network already set up at the Preferences > Network > Host-only Networks tab.
  # Each adapter has an IPv4 address + a IPv4 Network Mask, and while addresses can be served by a VirtualBox DHCP server
  # Proxmox PVE is best set up with a static address on the Host-Only network.

  def make_new_hostonly(vm)
      puts "NOT IMPLEMENTED - MAKE YOUR HOSTONLY NETWORK"

  # See # vagrant-1.6.5/plugins/providers/virtualbox/driver/version_4_3.rb#create_host_only_network(options)
  #    create_host_only_network(HOSTONLY, { })
  #    return network_details

   end

  def make_vbox_host_only_network(name, ipconfig)
      run_shell_cmd("VBoxManage hostonlyif #{ipconfig} #{name} create")
  end


  def route_host_to_containers(container_network_cidr, hostonly_gateway)
    run_shell_cmd("route add -net #{container_network_cidr} gw 192.168.4.2")
  end






