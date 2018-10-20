#!/bin/bash

game_dir=$1
home_id=$2
game_instance_dir=$game_dir/$home_id

configNamespace='{{(datasource "config").namespace}}'

dockerNamespace='{{if (datasource "globalConfig").docker_hub_namespace}}{{(datasource "globalConfig").docker_hub_namespace}}{{end}}'
gcloudNamespace='{{if (datasource "globalConfig").docker_gcloud_namespace }}{{(datasource "globalConfig").docker_gcloud_namespace}}{{end}}'

if [ ! -z "$dockerNamespace" ] && [ "$configNamespace" = "$dockerNamespace" ]; then
    echo "Using dockerhub"
    exit 0
    # Dockerhub services can be installed on the worker
fi

if [ ! -z "$gcloudNamespace" ] && [ "$configNamespace" = "$gcloudNamespace" ]; then
    echo "Using gcloud"
    docker stack rm $home_id'_install';
    sleep 10;
    docker stack deploy -c $game_instance_dir/docker-compose.install.yml $home_id'_install';
    exit 0
    # image will be downloaded in the background
fi

if [ ! -z "$dockerNamespace" ] || [ ! -z "$gcloudNamespace" ]; then
    echo "Namespace error" #TODO. make this blocking
    exit 1
    # If a namespace is defined, the image must match one of them
fi

exit 0

