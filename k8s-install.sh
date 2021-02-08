#!/bin/bash

# OS version
OS=CentOS_8
# CRIO version
VERSION=1.20

# Enable kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Configure networking
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system

# Disable SELinux for kubelet
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Disable swap
sed -i /swap/d /etc/fstab
swapoff -a

# Configure the firewall
dnf install iproute-tc firewalld -y
systemctl enable --now firewalld
firewall-cmd --permanent --zone=public --add-port=6443/tcp --add-port=10250/tcp
firewall-cmd --add-masquerade --permanent # allow internet access from containers

# Install crio
curl -L -o /etc/yum.repos.d/lib.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/devel:kubic:libcontainers:stable.repo
curl -L -o /etc/yum.repos.d/crio.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
dnf install cri-o -y

# Disable crio network, network will be handled by flannel
cat <<EOF > /etc/cni/net.d/100-crio-bridge.conf
{
    "cniVersion": "0.3.1",
    "name": "crio",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "hairpinMode": true,
    "ipam": {
        "type": "host-local",
        "routes": [
            { "dst": "0.0.0.0/0" },
            { "dst": "1100:200::1/24" }
        ],
        "ranges": [
        ]
    }
}
EOF

systemctl daemon-reload
systemctl enable --now crio

# Install kubeadm
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable kubelet

# Configure kubelet
echo "KUBELET_EXTRA_ARGS=--runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice" > /etc/sysconfig/kubelet

# Configure cluster
secret=$(kubeadm token generate)
hostname=$(hostname -f)
domain=$(hostname -d)

if [ ! -f kubeadm-init.yaml ]; then
    cat <<EOF > kubeadm-init.yaml
apiVersion: kubeadm.k8s.io/v1beta2
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: $secret
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  bindPort: 6443
nodeRegistration:
  criSocket: unix://var/run/crio/crio.sock
  name: $hostname
  taints:
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
---
apiServer:
  certSANs:
  - $hostname
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta2
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: k8s.gcr.io
kind: ClusterConfiguration
kubernetesVersion: v1.20.0
networking:
  dnsDomain: ns.local
  serviceSubnet: 10.96.0.0/14
  podSubnet: 10.244.0.0/16
scheduler: {}
controlPlaneEndpoint: $hostname
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
fi

# Apply cluste config, if needed
if [ ! -f /etc/kubernetes/admin.conf ]; then
    kubeadm init --config kubeadm-init.yaml
fi

# Configure kubectl env variable
grep -q 'KUBECONFIG' ~/.bashrc || echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> ~/.bashrc
export KUBECONFIG=/etc/kubernetes/admin.conf

# Enable execution of applications inside the control plane
kubectl taint nodes --all node-role.kubernetes.io/master-

# Configure pod networks with flannel
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
