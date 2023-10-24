#!/bin/bash

echo -n "Is this a master node? (y/n): "
read isMaster

# Commands for all nodes (master + workers)
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

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

VERSION=1.22
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_8/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:ALL:cri-o:${VERSION}.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:${VERSION}/CentOS_8/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo
sudo dnf -y install cri-o cri-tools
sudo systemctl enable --now crio

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

# Master node specific commands
if [ "$isMaster" = "y" ]; then
  sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 2379:2380 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 10259 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 10257 -j ACCEPT
fi

# Worker node specific commands
if [ "$isMaster" = "n" ]; then
  sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT
  sudo iptables -A INPUT -p tcp --dport 30000:32767 -j ACCEPT
fi
