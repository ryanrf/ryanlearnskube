#!/bin/bash -xe

setup(){
# Install Deps
sudo apt-get update
  sudo apt-get -y install socat conntrack ipset


# grab binaries
wget -q --show-progress --https-only --timestamping \
  https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.0.0-beta.0/crictl-v1.0.0-beta.0-linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-the-hard-way/runsc \
  https://github.com/opencontainers/runc/releases/download/v1.0.0-rc5/runc.amd64 \
  https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz \
  https://github.com/containerd/containerd/releases/download/v1.1.0/containerd-1.1.0.linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubelet

sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

chmod +x kubectl kube-proxy kubelet runc.amd64 runsc
  sudo mv runc.amd64 runc
  sudo mv kubectl kube-proxy kubelet runc runsc /usr/local/bin/
  sudo tar -xvf crictl-v1.0.0-beta.0-linux-amd64.tar.gz -C /usr/local/bin/
  sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/
  sudo tar -xvf containerd-1.1.0.linux-amd64.tar.gz -C /
}

systemd_service(){
	if [[ -z "$1" ]]
	then
		echo "systemd_service: missing service name"
	fi
	SERVICE=$1
	sudo systemctl daemon-reload
  sudo systemctl enable $SERVICE
  sudo systemctl start $SERVICE
}

configure_cni(){
POD_CIDR=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/pod-cidr)

printf '{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}' | sudo tee /etc/cni/net.d/10-bridge.conf

printf '{
    "cniVersion": "0.3.1",
    "type": "loopback"
}' | sudo tee /etc/cni/net.d/99-loopback.conf

}

configure_containerd(){
sudo mkdir -p /etc/containerd/

printf '[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/run/containerd/runsc"' | sudo tee /etc/containerd/config.toml

printf '[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target' | sudo tee /etc/systemd/system/containerd.service

systemd_service containerd
}

configure_kubelet(){
	for i in ${HOSTNAME}-key.pem ${HOSTNAME}.pem ${HOSTNAME}.kubeconfig ca.pem
	do
		if [[ -f "$i" ]]
		then
			case $i in
				${HOSTNAME}-key.pem)
					sudo mv ${HOSTNAME}-key.pem /var/lib/kubelet/
					;;
				${HOSTNAME}.pem)
					sudo mv ${HOSTNAME}.pem /var/lib/kubelet/
					;;
				${HOSTNAME}.kubeconfig)
					sudo mv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig
					;;
					ca.pem)
						sudo mv ca.pem /var/lib/kubernetes/
					;;
					*)
						echo "Unknown file"
						exit 1
						;;
			esac
		fi
	done
	
	printf "kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: '/var/lib/kubernetes/ca.pem'
authorization:
  mode: Webhook
clusterDomain: 'cluster.local'
clusterDNS:
  - '10.32.0.10'
podCIDR: '${POD_CIDR}'
runtimeRequestTimeout: '15m'
tlsCertFile: '/var/lib/kubelet/${HOSTNAME}.pem'
tlsPrivateKeyFile: '/var/lib/kubelet/${HOSTNAME}-key.pem'" | sudo tee /var/lib/kubelet/kubelet-config.yaml

printf '[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target' | sudo tee /etc/systemd/system/kubelet.service

systemd_service kubelet

}

configure_kubeproxy(){
	if [[ -f kube-proxy.kubeconfig ]]
	then
		sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
	fi

	printf 'kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"' | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml

printf '[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target' | sudo tee /etc/systemd/system/kube-proxy.service

systemd_service kube-proxy

}

for instance in worker-{0..2}
do
	gcloud compute ssh ${instance} --command "$(typeset -f setup); setup"
	for service in configure_cni configure_containerd configure_kubelet configure_kubeproxy
	do
		gcloud compute ssh ${instance} --command "$(typeset -f systemd_service ${service}); ${service}"
	done
done
