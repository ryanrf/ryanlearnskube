#!/bin/bash -xe

# Check all the necessary files are present
for i in worker-{0..2}.kubeconfig kube-proxy.kubeconfig admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig; do
	if [[ ! -f $i ]]
	then
		echo "$i is missing. Exiting..."
		exit 1
	fi
done 


for instance in worker-{0..2}; do
  gcloud compute scp ${instance}.kubeconfig kube-proxy.kubeconfig ${instance}:~/
done

for instance in controller-{0..2}; do
  gcloud compute scp admin.kubeconfig kube-controller-manager.kubeconfig kube-scheduler.kubeconfig ${instance}:~/
done
