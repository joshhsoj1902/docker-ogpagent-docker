#!/bin/bash

game_dir=$1
home_id=$2
game_instance_dir=$game_dir/$home_id

echo 'homeid: '$home_id
echo 'game dir: '$game_instance_dir

gomplate = '/usr/local/bin/gomplate';
configdatasource = 'config=file://' . $game_instance_dir . '/docker-config.yml';
binddatasource = 'bind=file://' . '/opt/OGP/Cfg/bind.yml';
template = '/opt/OGP/templates/docker-compose.tmpl';
output = $game_instance_dir . '/docker-compose.yml';

/usr/local/bin/gomplate -d $configdatasource -d $binddatasource -f $template -o $output

cat $game_instance_dir'/docker-environment.yml >> ' $output

#   my $gomplate_cmd = $gomplate . ' -d ' . $configdatasource . ' -d ' . $binddatasource . ' -f ' . $template . ' -o ' . $output;

#   logger 'The gomplate command: ' . $gomplate_cmd;

#   sudo_exec_without_decrypt($gomplate_cmd);

#   my $append_env_cmd = 'cat ' . $game_instance_dir . '/docker-environment.yml >> ' . $output;
#   sudo_exec_without_decrypt($append_env_cmd);