#!/bin/bash

home_id=$1

configNamespace='{{(datasource "config").namespace}}'

dockerNamespace='{{(datasource "globalConfig").docker_hub_namespace}}'
gcloudNamespace='{{(datasource "globalConfig").docker_gcloud_namespace}}'

if [ ${#dockerNamespace} -gt 0 ] && [ "$configNamespace" = "$dockerNamespace" ]; then
    echo "Using dockerhub"
    exit 0
    # Dockerhub services can be installed on the worker
fi

if [ ${#gcloudNamespace} -gt 0 ] && [ "$configNamespace" = "$gcloudNamespace" ]; then
    echo "Using gcloud"
    docker stack deploy -c docker-compose.install.yml $home_id'_install';
    exit 0
    # image will be downloaded in the background
fi

if [ ${#dockerNamespace} -gt 0 ] || [ ${#gcloudNamespace} -gt 0 ]; then
    echo "Namespace error" #TODO. make this blocking
    exit 1
    # If a namespace is defined, the image must match one of them
fi

exit 0

