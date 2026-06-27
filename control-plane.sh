#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root: sudo bash $0"
  exit 1
fi

echo "🔹 Updating system..."
rm -f /etc/apt/sources.list.d/kubernetes.list
rm -f /usr/share/keyrings/kubernetes-archive-keyring.gpg
apt-get update -y

echo "🔹 Disabling swap..."
swapoff -a
sed -i.bak '/ swap / s/^/#/' /etc/fstab

echo "🔹 Loading kernel modules..."
cat <<'EOT' > /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOT

modprobe overlay
modprobe br_netfilter

echo "🔹 Setting sysctl params..."
cat <<'EOT' > /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOT

sysctl --system

echo "🔹 Installing containerd..."
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release containerd

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "🔹 Installing Kubernetes packages..."
mkdir -p /usr/share/keyrings
rm -f /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null || true
cat <<'EOT' > /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /
EOT
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "🔹 Initializing Kubernetes cluster..."
kubeadm init --pod-network-cidr=192.168.0.0/16

echo "🔹 Configuring kubectl for ubuntu user..."
mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

echo "🔹 Installing Calico CNI..."
runuser -l ubuntu -c 'kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml'

echo "🔹 Generating worker join command..."
kubeadm token create --print-join-command > /join-command.sh
chmod +x /join-command.sh

cat /join-command.sh

echo ""
echo "===================================================="
echo "✅ CONTROL PLANE READY"
echo "👉 Copy this command and run it on the worker node:" 

echo "===================================================="
