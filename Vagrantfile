# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|

  config.vm.define "storage-provider.example.com" do |node|
    node.vm.box = "generic/alma8"
    node.vm.hostname = "storage-provider.example.com"
    node.vm.provision :shell, inline: "yum install -y rsync"
  end

end
