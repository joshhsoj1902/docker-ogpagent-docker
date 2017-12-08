#!/bin/bash

service_name=$1

service_count = $(sudo docker service ls --format='{{.Name}}' | grep -oh "$service_name" | wc -w)
echo 'service count' $service_count
  # my $docker_replicas = sudo_exec_without_decrypt($docker_service_cmd);

if [ "$service_count" -gt "0"]
then
    service_replicas = $(sudo docker service inspect --format='{{.Spec.Mode.Replicated.Replicas}}' $service_name)
    echo 1
else
    echo 0
fi

#   if ($service_count > 0) {
#     my $docker_service_replicas = `sudo docker service inspect --format='{{.Spec.Mode.Replicated.Replicas}}'' $service_name `;



# 	if ($docker_service_replicas > 0) {
# 	  logger 'Service running ' . $docker_service_replicas;
#       return 1;
# 	}
# 	else
# 	{
# 	  logger 'Service has no replicas ' . $docker_service_replicas;
#       return 0;
# 	}
#   }
#   else
#   {
#     logger 'Service is not up ' . $docker_service;
#     return 0;
#   }
#   fi