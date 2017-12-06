
Vagrant.require_version ">= 1.7.0"

$os_image = (ENV['OS_IMAGE'] || "centos7").to_sym

Vagrant.configure("2") do |config|

  config.vm.provider "virtualbox"
#  config.vm.synced_folder "ssh", "/home/vagrant/.ssh"
  config.vm.synced_folder "softs", "/home/vagrant/softs"
  config.vm.synced_folder "pki", "/home/vagrant/pki"
  config.vm.provision "shell", path: "provision-1-init.sh"
  master = 1
  node = 2
  # Set virtualbox func
  def set_vbox(vb, config, memory)
    vb.gui = false
    vb.memory = memory 
    vb.cpus = 2

    case $os_image
    when :centos7
      config.vm.box = "centos7"
    when :ubuntu16
      config.vm.box = "bento/ubuntu-16.04"
    end
  end

  private_count = 10
  (1..(master + node)).each do |mid|
    name = (mid <= node) ? "node" : "master"
    id   = (mid <= node) ? mid : (mid - node)
    memory = (mid <= node) ? 1024 : 2048

    config.vm.define "#{name}#{id}" do |n|
      n.vm.hostname = "#{name}#{id}"
      ip_addr = "172.1.1.#{private_count}"
      n.vm.network :private_network, ip: "#{ip_addr}",  auto_config: true

      n.vm.provider :virtualbox do |vb, override|
        vb.name = "kube-centos-#{n.vm.hostname}"
        set_vbox(vb, override, memory)
      end
      private_count += 1
    end
  end
end
