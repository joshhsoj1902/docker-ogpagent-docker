#!/bin/bash

home_id=$1
game_instance_dir=$OGP_GAME_DIR/$home_id

mkdir -p $game_instance_dir
touch $game_instance_dir'/docker-environment.yml'
touch $game_instance_dir'/docker-config.yml'
touch $game_instance_dir'/docker-test.yml'

chmod 777 -R $game_instance_dir