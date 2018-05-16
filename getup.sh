#!/bin/bash -ex

CONFIG=getup.config

confirm_continue(){
while true
do
	echo "$1"
  read ANSWER
  case $ANSWER in
    [yY]) echo "continuing..."
          break
          ;;
    [nN]) echo "exiting..."
          exit 0
          ;;
      *) echo "didn't understand response. Please try again"
          ;;
  esac
done
}

get_external_ip(){
  if [[ -z $1 ]]
  then
    echo "get_external_ip requires one argument. Please provide the name of the instance."
    exit 1
  fi
  local instance=$1
  gcloud compute instances describe ${instance} \
	  --format 'value(networkInterfaces[0].accessConfigs[0].natIP)'
}

get_internal_ip(){
  if [[ -z $1 ]]
  then
    echo "get_internal_ip requires one argument. Please provide the name of the instance."
    exit 1
  fi
  local instance=$1
	gcloud compute instances describe ${instance} \
		--format 'value(networkInterfaces[0].networkIP)'
}

get_kube_public_addr(){
  gcloud compute addresses describe kubernetes-the-hard-way \
	  --region $(gcloud config get-value compute/region) \
	  --format 'value(address)'
}

gcloud_create_networking(){
  # Create VPC:
  gcloud compute networks create kubernetes-the-hard-way --subnet-mode custom
  # Create subnet
  gcloud compute networks subnets create kubernetes \
    --network kubernetes-the-hard-way \
    --range 10.240.0.0/24

  # Create a firewall rule that allows internal communication across all protocols:

  gcloud compute firewall-rules create kubernetes-the-hard-way-allow-internal \
    --allow tcp,udp,icmp \
    --network kubernetes-the-hard-way \
    --source-ranges 10.240.0.0/24,10.200.0.0/16

  # Create a firewall rule that allows external SSH, ICMP, and HTTPS:

  gcloud compute firewall-rules create kubernetes-the-hard-way-allow-external \
    --allow tcp:22,tcp:6443,icmp \
    --network kubernetes-the-hard-way \
    --source-ranges 0.0.0.0/0

  # List the firewall rules in the kubernetes-the-hard-way VPC network:
  gcloud compute firewall-rules list --filter="network:kubernetes-the-hard-way"

  # Allocate a static IP address that will be attached to the external load balancer fronting the Kubernetes API Servers:
  gcloud compute addresses create kubernetes-the-hard-way \
    --region $(gcloud config get-value compute/region)
}

# Verify the `kubernetes-the-hard-way` static IP address was created in your default compute region:

gcloud compute addresses list --filter="name=('kubernetes-the-hard-way')"


gcloud_create_compute(){
	# Create three compute instances which will host the Kubernetes control plane, and three compute instances to act as worker nodes:
	# The following allows for a number to be passed to the function to be used as a workers count.
	# The function should be called in this manner: `gcloud_create_compute worker 5` or `gcloud_create_compute controller 3`
	TYPE=${1:=worker}
	END_INDEX=${2:=3}
	COUNT=$(expr $END_INDEX - 1)
	
	if [[ -gt "$END_INDEX" "9"]]
	then
	    echo "Number of workers or controllers must be less than 9"
	    exit 1
	fi
	
	case $TYPE in
	    worker)
	      IP_PREFIX=10.240.0.2
	      METADATA="--metadata pod-cidr=10.200.${i}.0/24"
	      ;;
	    controller)
	      IP_PREFIX=10.240.0.1
	      METADATA=""
	    *)
	      echo "unknown type $TYPE"
	      ;;
	esac
	
	for i in {0..$COUNT}; do
	  gcloud compute instances create $TYPE-${i} \
	    --async \
	    --boot-disk-size 200GB \
	    --can-ip-forward \
	    --image-family ubuntu-1604-lts \
	    --image-project ubuntu-os-cloud \
	    --machine-type n1-standard-1 \
	    --private-network-ip ${IP_PREFIX}${i} \
	    $METADATA \
	    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
	    --subnet kubernetes \
	    --tags kubernetes-the-hard-way,$TYPE
	done
	
	
	#   gcloud compute instances create worker-${i} \
	#     --async \
	#     --boot-disk-size 200GB \
	#     --can-ip-forward \
	#     --image-family ubuntu-1604-lts \
	#     --image-project ubuntu-os-cloud \
	#     --machine-type n1-standard-1 \
	#     --metadata pod-cidr=10.200.${i}.0/24 \
	#     --private-network-ip 10.240.0.2${i} \
	#     --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
	#     --subnet kubernetes \
	#     --tags kubernetes-the-hard-way,worker
	# done
}

# Verify
gcloud compute instances list

#create_certs(){
	local CITY=$1
	local PROVINCE=$2
	local COUNTRY=$3
	# The following would normally run in a for loop on each worker, where ${instance} is one of worker-1, worker-2, worker-3
	local EXTERNAL_IP=$(gcloud compute instances describe ${instance} \
	  		--format 'value(networkInterfaces[0].accessConfigs[0].natIP)')
	local INTERNAL_IP=$(gcloud compute instances describe ${instance} \
	  		--format 'value(networkInterfaces[0].networkIP)')


	
create_ca_certs(){
  # Creates ca csr, cert and (json) config file, for use with cfssl
	# Create the CA certificate signing request:
	unset COUNTRY
	unset CITY
	unset PROVINCE
	source $CONFIG
	
  cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$COUNTRY",
      "L": "$CITY",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "$PROVINCE"
    }
  ]
}
EOF
	
	#Generate the CA certificate and private key:
	
		cfssl gencert -initca ca-csr.json | cfssljson -bare ca

  #Create the CA configuration file:
  cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF
	
}
	
	
create_admin_cert(){
  if [[ -f ca-config.json ]]
  then
    echo "missing ca-config.json. Please run the `create_ca_certs` function."
    exit 1
  fi
  source $CONFIG
	#Create the `admin` client certificate signing request:
	
  cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$COUNTRY",
      "L": "$CITY",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "$PROVINCE"
    }
  ]
}
EOF
	
	
	
	#Generate the `admin` client certificate and private key:
		cfssl gencert \
	  	-ca=ca.pem \
	  	-ca-key=ca-key.pem \
	  	-config=ca-config.json \
	  	-profile=kubernetes \
	  	admin-csr.json | cfssljson -bare admin
}

create_workers_cert(){
#Generate a certificate and private key for each Kubernetes worker node:
  
  source $CONFIG
  local COUND=${1:=3}
  local END_INDEX=${expr $COUNT - 1}

	for i in {0..$END_INDEX}; do
    instance="worker-${i}"
    local EXTERNAL_IP=$(get_external_ip ${instance})
	  local INTERNAL_IP=$(get_internal_ip ${instance})
		cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$COUNTRY",
      "L": "$CITY",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "$PROVINCE"
    }
  ]
}
EOF

		cfssl gencert \
		  -ca=ca.pem \
		  -ca-key=ca-key.pem \
		  -config=ca-config.json \
		  -hostname=${instance},${EXTERNAL_IP},${INTERNAL_IP} \
		  -profile=kubernetes \
		  ${instance}-csr.json | cfssljson -bare ${instance}
	done
}

create_kube_proxy_cert(){
  #Create the `kube-proxy` client certificate signing request:
  source $CONFIG
	cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$COUNTRY",
      "L": "$CITY",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "$PROVINCE"
    }
  ]
}
EOF


#Generate the `kube-proxy` client certificate and private key:

	cfssl gencert \
	  -ca=ca.pem \
	  -ca-key=ca-key.pem \
	  -config=ca-config.json \
	  -profile=kubernetes \
	  kube-proxy-csr.json | cfssljson -bare kube-proxy
}



#Retrieve the `kubernetes-the-hard-way` static IP address:

	# KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
	#   --region $(gcloud config get-value compute/region) \
	#   --format 'value(address)')

create_kube_api_cert(){
  # Create the Kubernetes API Server certificate signing request:
  local KUBERNETES_PUBLIC_ADDRESS=$(get_kube_public_addr)
	cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "$COUNTRY",
      "L": "$CITY",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "$PROVINCE"
    }
  ]
}
EOF


# Generate the Kubernetes API Server certificate and private key:

	cfssl gencert \
	  -ca=ca.pem \
	  -ca-key=ca-key.pem \
	  -config=ca-config.json \
	  -hostname=10.32.0.1,10.240.0.10,10.240.0.11,10.240.0.12,${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,kubernetes.default \
	  -profile=kubernetes \
	  kubernetes-csr.json | cfssljson -bare kubernetes
}
--------------------------------------------------------------------
#### Distribute the Client and Server Certificates

# Copy the appropriate certificates and private keys to each worker instance:

for instance in worker-0 worker-1 worker-2; do
  gcloud compute scp ca.pem ${instance}-key.pem ${instance}.pem ${instance}:~/
done

# Copy the appropriate certificates and private keys to each controller instance:

for instance in controller-0 controller-1 controller-2; do
  gcloud compute scp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem ${instance}:~/
done

---------------------------------------------------------------------

# Kube configs

### Kubernetes Public IP Address

#Each kubeconfig requires a Kubernetes API Server to connect to. To support high availability the IP address assigned to the external load balancer fronting the Kubernetes API Servers will be used.

#Retrieve the `kubernetes-the-hard-way` static IP address:

# KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
#   --region $(gcloud config get-value compute/region) \
#   --format 'value(address)')

create_kubeconfig(){
  local KUBERNETES_PUBLIC_ADDRESS=$(get_kube_public_addr)
# Generate a kubeconfig file for each worker node:

	for instance in worker-0 worker-1 worker-2; do
	  kubectl config set-cluster kubernetes-the-hard-way \
	    --certificate-authority=ca.pem \
	    --embed-certs=true \
	    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
	    --kubeconfig=${instance}.kubeconfig
	
	  kubectl config set-credentials system:node:${instance} \
	    --client-certificate=${instance}.pem \
	    --client-key=${instance}-key.pem \
	    --embed-certs=true \
	    --kubeconfig=${instance}.kubeconfig
	
	  kubectl config set-context default \
	    --cluster=kubernetes-the-hard-way \
	    --user=system:node:${instance} \
	    --kubeconfig=${instance}.kubeconfig
	
	  kubectl config use-context default --kubeconfig=${instance}.kubeconfig
	done


# Generate a kubeconfig file for the `kube-proxy` service:

	kubectl config set-cluster kubernetes-the-hard-way \
	  --certificate-authority=ca.pem \
	  --embed-certs=true \
	  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
	  --kubeconfig=kube-proxy.kubeconfig
	
	kubectl config set-credentials kube-proxy \
	  --client-certificate=kube-proxy.pem \
	  --client-key=kube-proxy-key.pem \
	  --embed-certs=true \
	  --kubeconfig=kube-proxy.kubeconfig
	
	kubectl config set-context default \
	  --cluster=kubernetes-the-hard-way \
	  --user=kube-proxy \
	  --kubeconfig=kube-proxy.kubeconfig
	
	
	kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
	
	
	for instance in worker-0 worker-1 worker-2; do
	  gcloud compute scp ${instance}.kubeconfig kube-proxy.kubeconfig ${instance}:~/
	done
}

encrypt(){

#Generate an encryption key:

ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)


#Create the `encryption-config.yaml` encryption config file:

	cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF


# Copy the `encryption-config.yaml` encryption config file to each controller instance:

	for instance in controller-0 controller-1 controller-2; do
	  gcloud compute scp encryption-config.yaml ${instance}:~/
	done
}


# Everything in the following function, create_etcd, must be run on each controller, you can use `typeset -f myfunc; myfunc` to output the function to the terminal, then the last invocation of the function to run it.
create_etcd(){

# Download the official etcd release binaries from the [coreos/etcd](https://github.com/coreos/etcd) GitHub project:

	wget -q --show-progress --https-only --timestamping \
  	"https://github.com/coreos/etcd/releases/download/v3.2.11/etcd-v3.2.11-linux-amd64.tar.gz"

# Extract and install the `etcd` server and the `etcdctl` command line utility:

	tar -xvf etcd-v3.2.11-linux-amd64.tar.gz

	sudo mv etcd-v3.2.11-linux-amd64/etcd* /usr/local/bin/

## Configure the etcd Server

	sudo mkdir -p /etc/etcd /var/lib/etcd
	
	sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
	
	INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
	  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)
	
# Each etcd member must have a unique name within an etcd cluster. Set the etcd name to match the hostname of the current compute instance:
	
	ETCD_NAME=$(hostname -s)
	
# Create the `etcd.service` systemd unit file:
	cat > etcd.service <<EOF
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster controller-0=https://10.240.0.10:2380,controller-1=https://10.240.0.11:2380,controller-2=https://10.240.0.12:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start the etcd Server
	
	sudo mv etcd.service /etc/systemd/system/
	
	sudo systemctl daemon-reload
	
	sudo systemctl enable etcd
	
	sudo systemctl start etcd
}

# Verify etcd cluster:

ETCDCTL_API=3 etcdctl member list

# The following must be run on each controller (see using typeset for running functions remotely)

create_control_plane(){

# Download the official Kubernetes release binaries:

	wget -q --show-progress --https-only --timestamping \
  	"https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-apiserver" \
  	"https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-controller-manager" \
  	"https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-scheduler" \
  	"https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubectl"


	chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
	sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

	sudo mkdir -p /var/lib/kubernetes/
	sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem encryption-config.yaml /var/lib/kubernetes/

# The instance internal IP address will be used to advertise the API Server to members of the cluster. Retrieve the internal IP address for the current compute instance:

	INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
  	http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

# Create the `kube-apiserver.service` systemd unit file:

	cat > kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --admission-control=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
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
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --insecure-bind-address=127.0.0.1 \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-ca-file=/var/lib/kubernetes/ca.pem \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create the `kube-controller-manager.service` systemd unit file:

	cat > kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --leader-elect=true \\
  --master=http://127.0.0.1:8080 \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/ca-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create the `kube-scheduler.service` systemd unit file:

	cat > kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --leader-elect=true \\
  --master=http://127.0.0.1:8080 \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo mv kube-apiserver.service kube-scheduler.service kube-controller-manager.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
}


kubectl get componentstatuses
# The following needs to be run on one of the controllers
create_kublet_rbac_auth(){

# Create the `system:kube-apiserver-to-kubelet` [ClusterRole](https://kubernetes.io/docs/admin/authorization/rbac/#role-and-clusterrole) with permissions to access the Kubelet API and perform most common tasks associated with managing pods:

	cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

# The Kubernetes API Server authenticates to the Kubelet as the `kubernetes` user using the client certificate as defined by the `--kubelet-client-certificate` flag.

# Bind the `system:kube-apiserver-to-kubelet` ClusterRole to the `kubernetes` user:

	cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

}

create_external_lb(){


# Create the external load balancer network resources:

gcloud compute target-pools create kubernetes-target-pool
gcloud compute target-pools add-instances kubernetes-target-pool \
  --instances controller-0,controller-1,controller-2

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
  --region $(gcloud config get-value compute/region) \
  --format 'value(name)')

gcloud compute forwarding-rules create kubernetes-forwarding-rule \
  --address ${KUBERNETES_PUBLIC_ADDRESS} \
  --ports 6443 \
  --region $(gcloud config get-value compute/region) \
  --target-pool kubernetes-target-pool

}

# Verification
KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
  --region $(gcloud config get-value compute/region) \
  --format 'value(address)')

# Make a HTTP request for the Kubernetes version info:

curl --cacert ca.pem https://${KUBERNETES_PUBLIC_ADDRESS}:6443/version


# The following must be run on all the workers. See using typeset to run functions remotely
configure_workers(){


## Provisioning a Kubernetes Worker Node

# Install the OS dependencies:

sudo apt-get -y install socat

# The socat binary enables support for the `kubectl port-forward` command.

### Download and Install Worker Binaries

wget -q --show-progress --https-only --timestamping \
  https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz \
  https://github.com/containerd/cri-containerd/releases/download/v1.0.0-beta.1/cri-containerd-1.0.0-beta.1.linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/v1.9.0/bin/linux/amd64/kubelet

# Create the installation directories:

sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

# Install the worker binaries:

sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/

sudo tar -xvf cri-containerd-1.0.0-beta.1.linux-amd64.tar.gz -C /

chmod +x kubectl kube-proxy kubelet

sudo mv kubectl kube-proxy kubelet /usr/local/bin/

# Configure CNI Networking

# Retrieve the Pod CIDR range for the current compute instance:

POD_CIDR=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/pod-cidr)

# Create the `bridge` network configuration file:

cat > 10-bridge.conf <<EOF
{
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
}
EOF

# Create the `loopback` network configuration file:

cat > 99-loopback.conf <<EOF
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF

# Move the network configuration files to the CNI configuration directory:

sudo mv 10-bridge.conf 99-loopback.conf /etc/cni/net.d/

# Configure the Kubelet

sudo mv ${HOSTNAME}-key.pem ${HOSTNAME}.pem /var/lib/kubelet/

sudo mv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig

sudo mv ca.pem /var/lib/kubernetes/

# Create the `kubelet.service` systemd unit file:

cat > kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=cri-containerd.service
Requires=cri-containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --allow-privileged=true \\
  --anonymous-auth=false \\
  --authorization-mode=Webhook \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --cloud-provider= \\
  --cluster-dns=10.32.0.10 \\
  --cluster-domain=cluster.local \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/cri-containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --pod-cidr=${POD_CIDR} \\
  --register-node=true \\
  --runtime-request-timeout=15m \\
  --tls-cert-file=/var/lib/kubelet/${HOSTNAME}.pem \\
  --tls-private-key-file=/var/lib/kubelet/${HOSTNAME}-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

}

# The following must be run on all the workers. See using typeset to run functions remotely
configure_kube_proxy(){


	sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

# Create the `kube-proxy.service` systemd unit file:

	cat > kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --cluster-cidr=10.200.0.0/16 \\
  --kubeconfig=/var/lib/kube-proxy/kubeconfig \\
  --proxy-mode=iptables \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start the Worker Services

sudo mv kubelet.service kube-proxy.service /etc/systemd/system/

sudo systemctl daemon-reload

sudo systemctl enable containerd cri-containerd kubelet kube-proxy

sudo systemctl start containerd cri-containerd kubelet kube-proxy

}

# Verification

gcloud compute ssh controller-0

# List the registered Kubernetes nodes:

kubectl get nodes

configure_kubectl(){

# Each kubeconfig requires a Kubernetes API Server to connect to. To support high availability the IP address assigned to the external load balancer fronting the Kubernetes API Servers will be used.

# Retrieve the `kubernetes-the-hard-way` static IP address:

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
  --region $(gcloud config get-value compute/region) \
  --format 'value(address)')

# Generate a kubeconfig file suitable for authenticating as the `admin` user:

kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443

kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem

kubectl config set-context kubernetes-the-hard-way \
  --cluster=kubernetes-the-hard-way \
  --user=admin

kubectl config use-context kubernetes-the-hard-way
}

# Verification
kubectl get componentstatuses

create_routes(){

for i in 0 1 2; do
  gcloud compute routes create kubernetes-route-10-200-${i}-0-24 \
    --network kubernetes-the-hard-way \
    --next-hop-address 10.240.0.2${i} \
    --destination-range 10.200.${i}.0/24
done
}

# Verficiation

gcloud compute routes list --filter "network: kubernetes-the-hard-way"

setup_dns(){
kubectl create -f https://storage.googleapis.com/kubernetes-the-hard-way/kube-dns.yaml
}

# Verification

# Create a `busybox` deployment:

kubectl run busybox --image=busybox --command -- sleep 3600

# List the pod created by the `busybox` deployment:

kubectl get pods -l run=busybox

#> output
#
#```
#NAME                       READY     STATUS    RESTARTS   AGE
#busybox-2125412808-mt2vb   1/1       Running   0          15s
#```

# Retrieve the full name of the `busybox` pod:

POD_NAME=$(kubectl get pods -l run=busybox -o jsonpath="{.items[0].metadata.name}")

# Execute a DNS lookup for the `kubernetes` service inside the `busybox` pod:

kubectl exec -ti $POD_NAME -- nslookup kubernetes

#> output
#
#Server:    10.32.0.10
#Address 1: 10.32.0.10 kube-dns.kube-system.svc.cluster.local
#
#Name:      kubernetes
#Address 1: 10.32.0.1 kubernetes.default.svc.cluster.local

# SMOKE TEST - Confirming the cluster is operating properly - refer to Kubernetes the hard way, doc, starting at 13.
