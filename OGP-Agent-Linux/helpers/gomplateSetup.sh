#!/bin/bash

game_dir=$1
home_id=$2
game_instance_dir=$game_dir/$home_id

echo 'homeid: '$home_id
echo 'game dir: '$game_instance_dir

echo 'homeId: '$home_id >> $game_instance_dir/home.yml

configdatasource='config=file://'$game_instance_dir'/docker-config.yml';
homedatasource='home=file://'$game_instance_dir'/home.yml';
binddatasource='bind=file:///opt/OGP/Cfg/bind.yml';
template='/opt/OGP/templates/docker-compose.tmpl.yml';
output=$game_instance_dir'/docker-compose.yml';

echo 'GOMPLATE: ' -d $configdatasource -d $homedatasource -d $binddatasource -f $template -o $output

/usr/local/bin/gomplate -d $configdatasource -d $homedatasource -d $binddatasource -f $template -o $output

cat $game_instance_dir'/docker-environment.yml' >> $output
