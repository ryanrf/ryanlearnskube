#!/bin/bash -xe
# source vars
source config

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
      "ST": "$STATE"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

