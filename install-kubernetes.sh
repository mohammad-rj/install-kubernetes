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

# Commands for all nodes (master + workers)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#/g' /etc/fstab
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo iptables -A INPUT -p tcp --dport 4240 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 8472 -j ACCEPT
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
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

# Install CRI-O (Automatically fetch the latest version)
VERSION=$(curl -s https://api.github.com/repos/cri-o/cri-o/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | cut -c 2-)
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_8/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:${VERSION}/CentOS_8/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo
sudo dnf -y install cri-o cri-tools
sudo systemctl enable --now crio

# Install Kubernetes
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

