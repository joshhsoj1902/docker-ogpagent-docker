#!/bin/bash

service_name=$1

service_count=$(docker service ls --format='{{.Name}}' | grep -oh "$service_name" | wc -w)
# echo 'service count' $service_count

if [ "$service_count" -gt "0" ]
then
    service_replicas=$(docker service inspect --format='{{.Spec.Mode.Replicated.Replicas}}' $service_name)
    echo $service_replicas
else
    echo 0
fi
