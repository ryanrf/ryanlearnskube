#!/bin/bash -xe

install_nginx(){
	sudo apt-get install -y nginx
	printf "server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}" | sudo tee /etc/nginx/sites-available/kubernetes.default.svc.cluster.local
	sudo systemctl restart nginx
	sudo systemctl enable nginx
	sudo ln -sf /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/
}

for instance in controller-{0..2}
do
	gcloud compute ssh ${instance} --command "$(typeset -f install_nginx); install_nginx"
done
