#!/bin/bash

DOCKER_PULL_IMAGES=("postgres:9.4.5" "redis:2.8.22")
COPY_UNIT_FILES=("postgres" "redis")

SERVER_IP="${SERVER_IP:-10.192.168.154}"
SSH_USER="${SSH_USER:-$(whoami)}"
KEY_USER="${KEY_USER:-$(whoami)}"
DOCKER_VERSION="${DOCKER_VERSION:-1.10.2}"

function preseed_staging() {
cat << EOF
STAGING SERVER (DIRECT VIRTUAL MACHINE) DIRECTIONS:
	1. Configure a static IP address directly on the VM
		su
		<enter password>
		nano /etc/network/interfaces
		[change the last line to look this, remember to set the correct
		gateway for your router's IP address if it's not 192.168.1.1]
	iface eth0 inet static
		address ${SERVER_IP}
		netmask 255.255.252.0
		gateway	10.192.168.16

	2. Reboot the VM and ensure the Debian CD is mounted
	3. Install sudo
		 apt-get update && apt-get install sudo -y -qq

	4. Add the user to the sudo group
		 adduser ${SSH_USER} sudo

	5. Run the commands in: $0 --help
		 Example:
		 	./deploy.sh -a
EOF
}
 
function configure_sudo() {
	echo "Configuring passwordless necessarysudo..."
	scp "sudo/sudoers" "${SSH_USER}@${SERVER_IP}:/tmp/sudoers"
	ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo chmod 440 /tmp/sudoers
sudo chown root:root /tmp/sudoers
sudo mv /tmp/sudoers /etc	
	'"
	echo "done!"
}

function add_ssh_key() {
	echo "Adding SSH key..."
	cat "$HOME/.ssh/id_rsa.pub" | ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
mkdir -p /home/${KEY_USER}/.ssh
cat >> /home/${KEY_USER}/.ssh/authorized_keys
	'"
	ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
chmod 700 /home/${KEY_USER}/.ssh
chmod 644 /home/${KEY_USER}/.ssh/authorized_keys
sudo chown ${KEY_USER}:${KEY_USER} -R /home/${KEY_USER}/.ssh
	'"
	echo "done!"
}

function configure_secure_ssh() {
	echo "Configuring secure SSH..."
	scp "ssh/sshd_config" "${SSH_USER}@${SERVER_IP}:/tmp/sshd_config"	
	ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo chown root:root /tmp/sshd_config
sudo mv /tmp/sshd_config /etc/ssh
sudo systemctl restart ssh
	'"
	echo "done!"
}

function install_docker() {
	echo "Configuring Docker v${DOCKER_VERSION}..."
	scp "docker/docker.list" "${SSH_USER}@${SERVER_IP}:/tmp/docker.list"
	ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo apt-get update
sudo apt-get install -y -q apt-transport-https ca-certificates
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
sudo cp /tmp/docker.list /etc/apt/sources.list.d/
sudo apt-get update
sudo apt-get install -y -q docker-engine
sudo usermod -aG docker "${KEY_USER}"
	'"
	echo "done!"
}

function docker_pull() {
	echo "Pulling Docker images..."
	for image in "${DOCKER_PULL_IMAGES[@]}"
	do
		ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'docker pull ${image}'"
	done
}

function git_init() {
	echo "Initialize git repo and hooks..."
	scp "git/post-receive/mobydock" "${SSH_USER}@${SERVER_IP}:/tmp/mobydock"
	ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo apt-get update && sudo apt-get install -y -q git
sudo rm -rf /var/git/mobydock.git /var/git/mobydock
sudo mkdir -p /var/git/mobydock.git /var/git/mobydock
sudo git --git-dir=/var/git/mobydock.git --bare init

sudo mv /tmp/mobydock /var/git/mobydock.git/hooks/post-receive
sudo chmod +x /var/git/mobydock.git/hooks/post-receive
sudo chown ${SSH_USER}:${SSH_USER} -R /var/git/mobydock.git /var/git/mobydock
	'"
	echo "done!"
}

function configure_firewall() {
	echo "Configuring iptables firewall..."
	scp "iptables/rules-save" "${SSH_USER}@${SERVER_IP}:/tmp/rules-save"
	ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo mkdir -p /var/lib/iptables
sudo mv /tmp/rules-save /var/lib/iptables
sudo chown root:root -R /var/lib/iptables
	'"
	echo "done!"
}

function copy-units() {
	echo "Copying systemd unit files..."
	for unit in "${COPY_UNIT_FILES[@]}"
	do
		scp "units/${unit}.service" "${SSH_USER}@${SERVER_IP}:/tmp/${unit}.service"	
		ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
sudo mv /tmp/${unit}.service /etc/systemd/system
sudo chown ${SSH_USER}:${SSH_USER} /etc/systemd/system/${unit}.service
	'"
	done 	
	echo "done!"
}

function provision_server() {
	configure_sudo
	echo "--------"
	add_ssh_key
	echo "--------"
	configure_secure_ssh
	echo "--------"
	install_docker
	echo "--------"
	docker_pull
	echo "--------"
	git_init
	echo "--------"
	configure_firewall
}

function help_menu() {
cat << EOF
Usage: ${0} (-h | -S | -u | -k | -s | -d [docker_ver] | -l | -g | -f | -c | -b | -a [docker_ver])

ENVIRONMENT VARIABLES:
	SERVER_IP	IP address of remote server, ie. staging or production
			Defaulting to ${SERVER_IP}
	SSH_USER	User account to ssh and scp in as
			Defaulting to ${SSH_USER}
	KEY_USER	User account linked to SSH key
			Defaulting to ${KEY_USER}
	DOCKER_VERSION	Docker engine version to install
			Defaulting to ${DOCKER_VERSION}

OPTIONS:
	-h|--help                 Show this message
	-S|--preseed_staging      Preseed instructions for the staging server
	-u|--sudo                 Configure passwordless sudo
	-k|--ssh-key              Add SSH key
	-s|--ssh                  Configure secure SSH
	-d|--docker               Install Docker
	-l|--docker-pull          Pull necessary Docker images
	-g|--git-init             Install and initialize git
	-f|--firewall             Configure IPTABLES firewall
	-c|--copy-units           Copy systemd unit files
	-b|--enable-base-units    Enable base systemd unit files
	-a|--all                  Provision everything except preseeding

EXAMPLES:
    Configure passwordless sudo:
    	$ deploy -u

    Add SSH key:
    	$ deploy -k

    Configure secure SSH:
    	$ deploy -s

    Install Docker v${DOCKER_VERSION}:
    	$ deploy -d

    Pull necessary Docker images:
    	$ deploy -l

    Install and initialize git:
    	$ deploy -g

    Configure the iptables firewall:
    	$ deploy -f

    Copy systemd unit files:
    	$ deploy -c

    Enable base systemd unit files:
    	$ deploy -b

    Configure everything together:
    	$ deploy -a

EOF
}


while [[ $# > 0 ]] 
do
case "$1" in
		-S|--preseed_staging)
		preseed_staging
		shift
		;;
		-u|--sudo)
		configure_sudo
		shift
		;;
		-k|--ssh-key)
		add_ssh_key
		shift
		;;
		-s|--ssh)
		configure_secure_ssh
		shift
		;;
		-d|--docker)
		install_docker
		shift
		;;
		-l|--docker-pull)
		docker_pull
		shift
		;;
		-g|--git-init)
		git_init
		shift
		;;
		-f|--firewall)
		configure_firewall
		shift
		;;
		-c|--copy-units)
		copy_units
		shift
		;;
		-b|--enable-base-units)
		enable_base_units
		shift
		;;
		-a|--all)
		provision_server
		shift
		;;
		-h|--help)
		help_menu
		shift
		;;
		*)
		echo "${1} is not a valid flag, try running: $0 --help"
		;;
esac
shift
done