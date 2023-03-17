#!/bin/bash

ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH="/run/share/zdmproxy_config_updates"

while [ $# -gt 0 ]
do
    config_name=${1//=*/}
    config_value=${1//*=/}
    if ! grep -q "$config_name" "$ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH"
    then
        echo "Appending '$config_name' to config env file, and setting its value to '$config_value'"
        echo "$config_name=$config_value" >> "$ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH"
    else
        echo "Setting '$config_name' in config env file to value '$config_value'"
        sed -i "s,^$config_name=.*,$config_name=$config_value,g" "$ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH"
    fi

    shift
done