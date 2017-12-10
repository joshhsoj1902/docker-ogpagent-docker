#!/bin/bash

configNameSpace={{(datasource "config").namespace}}
configImage={{(datasource "config").image}}
configVersion={{(datasource "config").version}}

dockerNameSpace={{(datasource "globalConfig").docker_hub_namespace}}
gcloudNamespace={{(datasource "globalConfig").docker_gcloud_namespace}}

if [ ${#dockerNameSpace} -gt 0 ] && [ "$configNameSpace" = "$dockerNameSpace" ]; then
    exit 0
    # Dockerhub services can be installed on the worker
fi

if [ ${#gcloudNamespace} -gt 0 ] && [ "$gcloudNamespace" = "$dockerNameSpace" ]; then
    docker stack deploy -c $game_instance_dir'/docker-compose.install.yml' $home_id'_install';
    exit 0
    # image will be downloaded in the background
fi

if [ ${#dockerNameSpace} -gt 0 ] || [ ${#gcloudNamespace} -gt 0 ]; then
    exit 1
    # If a namespace is defined, the image must match one of them
fi

exit 0

