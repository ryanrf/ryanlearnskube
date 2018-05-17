#!/bin/bash -xe
# This script copies all certs to the workers and instances

# Check all files exist
FAIL=false
for i in worker-{0..2}.pem service-account.pem service-account-key.pem ca-key.pem kubernetes-key.pem kubernetes.pem; do
	test -f $i || FAIL=true
	if [[ "$FAIL" == "true" ]]
	then
		echo "$i is missing. Exiting"
		exit 1
	fi
done

for instance in worker-0 worker-1 worker-2; do
  gcloud compute scp ca.pem ${instance}-key.pem ${instance}.pem ${instance}:~/
done

for instance in controller-0 controller-1 controller-2; do
  gcloud compute scp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
    service-account-key.pem service-account.pem ${instance}:~/
done
