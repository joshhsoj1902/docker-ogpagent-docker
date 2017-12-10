#!/bin/bash

game_dir=$1
home_id=$2
game_instance_dir=$game_dir/$home_id

echo 'homeid: '$home_id
echo 'game dir: '$game_instance_dir

configdatasource='config=file://'$game_instance_dir'/docker-config.yml';
binddatasource='bind=file:///opt/OGP/Cfg/bind.yml';
template='/opt/OGP/templates/docker-compose.tmpl';
output=$game_instance_dir'/docker-compose.yml';

echo 'GOMPLATE: ' -d $configdatasource -d $binddatasource -f $template -o $output

/usr/local/bin/gomplate -d $configdatasource -d $binddatasource -f $template -o $output

cat $game_instance_dir'/docker-environment.yml' >> $output
