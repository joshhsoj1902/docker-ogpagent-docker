#!/bin/bash

/usr/local/bin/gomplate -f /opt/OGP/templates/Config.pm.tmpl -o /opt/OGP/Cfg/Config.pm
/usr/local/bin/gomplate -f /opt/OGP/templates/Config.tmpl.yml -o /opt/OGP/Cfg/Config.yml
/usr/local/bin/gomplate -f /opt/OGP/templates/Preferences.pm.tmpl -o /opt/OGP/Cfg/Preferences.pm

echo 'storage: '${STORAGE} >> /opt/OGP/Cfg/Config.yml
echo 'storage_nfs_address: '${STORAGE_NFS_ADDRESS} >> /opt/OGP/Cfg/Config.yml
echo 'storage_nfs_path: '${STORAGE_NFS_PATH} >> /opt/OGP/Cfg/Config.yml
# echo 'docker_hub_namespace: '${OGP_DOCKER_NAMESPACE} >> /opt/OGP/Cfg/Config.yml
# echo 'docker_gcloud_namespace: '${OGP_GCLOUD_NAMESPACE} >> /opt/OGP/Cfg/Config.yml

chmod +x /opt/OGP/ogp_agent_run
echo "Starting DockerOGP"

tail -F /opt/OGP/ogp_agent.log &

su ogp_agent -c "cd /opt/OGP/; ./ogp_agent_run"
