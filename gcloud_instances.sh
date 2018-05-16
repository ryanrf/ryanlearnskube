#!/bin/bash
PROJECT=ryanlearnskubernetes
usage(){
	echo "$(basename $0) [start|stop]"
	exit 1
}

if [[ -z "$1" ]]
then
	usage
fi

gcloud compute instances $1 $(gcloud compute instances list --project ryanlearnskubernetes | awk 'NR>1 {print $1}')
