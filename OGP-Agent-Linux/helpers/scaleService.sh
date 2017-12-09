#!/bin/bash

service_name=$1
replicas=$2

docker service scale $service_name=$replicas

