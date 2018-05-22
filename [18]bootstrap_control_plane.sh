#!/bin/bash -xe

setup(){
	# Create config dir
	sudo mkdir -p /etc/kubernetes/config
	
	# Grab binaries
	wget -q --show-progress --https-only --timestamping \
	  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-apiserver" \
	  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-controller-manager" \
	  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-scheduler" \
	  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl"
	
	# Install binaries
	chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
	sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
	
	# config API server
	sudo mkdir -p /var/lib/kubernetes/
	for file in ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem service-account-key.pem service-account.pem encryption-config.yaml
	do
		if [[ ! -f /var/lib/kubernetes/${file} ]]
		then
			sudo mv ${file} /var/lib/kubernetes
		fi
	done
}

systemd_service(){
	if [[ -z "$1" ]]
	then
		echo "missing service name"
		exit 1
	fi
	local SERVICE=$1
	sudo systemctl daemon-reload
  sudo systemctl enable $SERVICE
  sudo systemctl start $SERVICE
}

install_api_server(){
	INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
	  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
	
	printf "[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/kube-apiserver.service

	systemd_service kube-apiserver

}

install_controller_manager(){
	sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/
	printf "[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/kube-controller-manager.service

systemd_service kube-controller-manager

}

install_scheduler(){
	sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/
	printf "apiVersion: componentconfig/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: '/var/lib/kubernetes/kube-scheduler.kubeconfig'
leaderElection:
  leaderElect: true" | sudo tee /etc/kubernetes/config/kube-scheduler.yaml

	printf "[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/kube-scheduler.service

systemd_service kube-scheduler

}



for instance in controller-{0..2}
do
	gcloud compute ssh ${instance} --command "$(typeset -f setup ); setup"
	for service in install_api_server install_controller_manager install_scheduler
	do
		gcloud compute ssh ${instance} --command "$(typeset -f $service);$(typeset -f systemd_service); $service"
	done
done
