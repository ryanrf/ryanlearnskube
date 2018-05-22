#!/bin/bash -xe

for instance in controller-{0..2}; do
  gcloud compute scp encryption-config.yaml ${instance}:~/
done
