#!/bin/bash

game_dir=$1
path=$2

if [[ $path == $game_dir* ]]; then
    parsed_path=${path#$game_dir}
    IFS='/';
    for word in $parsed_path; do
        re='^[0-9]+$'
        if [[ $word =~ $re ]] ; then
                echo $word;
                exit 0;
        fi
    done
fi

exit 1;