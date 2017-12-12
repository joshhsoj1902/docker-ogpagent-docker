#!/bin/bash

service_name=$1

service_count=$(docker service ls --format='{{.Name}}' | grep -oh "$service_name" | wc -w)
# echo 'service count' $service_count

if [ "$service_count" -gt "0" ]
then
    service_replicas=$(docker service ls --format='{{.Replicas}}' --filter name=$service_name)
    IFS='/';
    for num in $service_replicas; do
        echo $num;
        exit;
    done
    echo $service_replicas
else
    echo 0
fi
