Vagrant.configure("2") do |config|
  config.vm.box = "hashicorp/bionic64"

  config.vm.network "private_network", ip: "192.168.33.10"

  # Sync host directory to /vagrant_data
  config.vm.synced_folder "./vagrant_data", "/vagrant_data"

  # Ensure rsync is installed
  config.vm.provision "shell", inline: <<-SHELL
    apt-get update
    apt-get install -y rsync
  SHELL
end
