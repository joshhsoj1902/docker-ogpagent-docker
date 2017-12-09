#!/bin/bash

home_id=$1
game_dir=$2
game_instance_dir=$game_dir/$home_id

echo 'homeid: '$home_id
echo 'game dir: '$game_instance_dir

mkdir -p $game_instance_dir
touch $game_instance_dir'/docker-environment.yml'
touch $game_instance_dir'/docker-config.yml'
touch $game_instance_dir'/docker-test.yml'

chmod 777 -R $game_instance_dir