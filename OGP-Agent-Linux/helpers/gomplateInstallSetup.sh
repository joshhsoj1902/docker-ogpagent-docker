#!/bin/bash

game_dir=$1
home_id=$2
game_instance_dir=$game_dir/$home_id

echo 'homeid: '$home_id
echo 'game dir: '$game_instance_dir

configdatasource='config=file://'$game_instance_dir'/docker-config.yml';
globalconfigdatasource='globalConfig=file:///opt/OGP/Cfg/config.yml';
templateShell='/opt/OGP/templates/install.tmpl.sh';
outputShell=$game_instance_dir'/install.sh';
templateCompose='/opt/OGP/templates/docker-compose.install.tmpl.yml';
outputCompose=$game_instance_dir'/docker-compose.install.yml';

echo 'GOMPLATE Shell: ' -d $configdatasource -d $globalconfigdatasource -f $templateShell -o $outputShell

/usr/local/bin/gomplate -d $configdatasource -d $globalconfigdatasource -f $templateShell -o $outputShell

chmod +x $outputShell

echo 'GOMPLATE compose: ' -d $configdatasource -f $templateShell -o $outputShell

/usr/local/bin/gomplate -d $configdatasource -f $templateCompose -o $outputCompose
