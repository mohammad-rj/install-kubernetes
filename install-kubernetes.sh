#!/bin/bash

# Prompt for master or worker node
while true; do
  echo -n "Is this a master node? (y/n): "
  read isMaster
  if [[ "$isMaster" == "y" || "$isMaster" == "n" ]]; then
    break
  else
    echo "Invalid input. Please enter 'y' for yes or 'n' for no."
  fi
done

# Update and upgrade packages
sudo yum -y update && sudo yum -y upgrade

# Common settings for all nodes (master + workers)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#/g' /etc/fstab
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo iptables -A INPUT -p tcp --dport 4240 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 8472 -j ACCEPT

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
 
sudo modprobe overlay
sudo modprobe br_netfilter
 
# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
 
# Apply sysctl params without reboot
sudo sysctl --system

# Master node specific settings
if [ "$isMaster" = "y" ]; then
  sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 2379:2380 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 10259 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 10257 -j ACCEPT
fi

# Worker node specific settings
if [ "$isMaster" = "n" ]; then
  sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 30000:32767 -j ACCEPT
fi

# Save iptables rules
sudo iptables-save > /etc/sysconfig/iptables

# Ensure the rules are restored at boot  
echo "iptables-restore < /etc/sysconfig/iptables" | sudo tee -a /etc/rc.d/rc.local
sudo chmod +x /etc/rc.d/rc.local

# Install CRI-O
OS=CentOS_9_Stream
VERSION=1.28
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/download/repositories/devel:/kubic:/libcontainers:/stable/${OS}/devel:kubic:libcontainers:stable.repo
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${VERSION}/${OS}/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo

sudo dnf -y install cri-o cri-tools
sudo systemctl enable --now crio
#sudo systemctl status crio

# Install Kubernetes
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet
#sudo systemctl status kubelet
