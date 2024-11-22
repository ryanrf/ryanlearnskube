# Kubernetes the Hard Way - notes
These are the scripts I used to help me learn and cement the ideas in (Kelsey Hightower's Kubernetes the hard way tutorial)[https://github.com/kelseyhightower/kubernetes-the-hard-way].
A few of the scripts rely on a config file, named `config`. It looks like:
```
CITY=Vancouver
STATE=BC
COUNTRY=CA

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
  --region $(gcloud config get-value compute/region) \
  --format 'value(address)')
```

This allows you to set your own values for the certificate information and, should you want to change the external IP to something static, there's that option too.

Here are some additions
To trigger cla-assistant
and another line
and... one more.
