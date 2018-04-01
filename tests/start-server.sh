#!/bin/bash

cat <<EOF > /opt/OGP/Cfg/Config.yml
storage: FOOBAR
storage_nfs_address: 
storage_nfs_path: 
docker_hub_namespace: 
docker_gcloud_namespace:
EOF

echo "== Setup Home =="
bash /opt/OGP/helpers/setupHome.sh /opt/games 1

mkdir -p /opt/games/1

cat <<EOF > /opt/games/1/docker-config.yml
port: 27015
namespace: joshhsoj1902 
image: linuxgsm-docker 
dataVol1: / 
maxplayers: 8
version: latest
EOF

cat <<EOF > /opt/games/1/docker-environment.yml
      - LGSM_GAMESERVERNAME=cssserver
      - LGSM_UPDATEINSTALLSKIP=UPDATE
EOF

echo "== Gomplate Setup =="
bash /opt/OGP/helpers/gomplateSetup.sh /opt/games 1

echo "== Gomplate Install Setup =="
bash /opt/OGP/helpers/gomplateInstallSetup.sh /opt/games 1

echo "== Start Service =="
bash /opt/OGP/helpers/startService.sh /opt/games 1      
