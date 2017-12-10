#!/bin/bash

game_dir=$1
home_id=$2
game_instance_dir=$game_dir/$home_id

docker stack deploy -c $game_instance_dir'/docker-compose.yml' $home_id;
