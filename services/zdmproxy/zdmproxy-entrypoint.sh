#!/bin/bash

error_abort_deployment() {
    local error_msg=("$@")

    echo "ERROR: ${error_msg[*]}"
    echo "Aborting ZDM Proxy deployment!"
    tail -F /dev/null # keeps container running
}

get_env_value() {
    # 1 - environment variable name
    eval "echo \$$(tr "[:lower:]" "[:upper:]" <<<"$1")"
}

set_env_value() {
    # 1 - environment variable name
    # 2 - value to set the environment variable to
    eval "$(tr "[:lower:]" "[:upper:]" <<<"$1")=$2"
}

export_env_value() {
    # 1 - environment variable name
    # 2 - value to set the environment variable to and export
    eval "export $(tr "[:lower:]" "[:upper:]" <<<"$1")=$2"
}

write_env_value() {
    # 1 - environment variable name
    # 2 - value to write for the variable
    # 3 - file to append to
    local config_name=""
    local config_value="$2"
    local config_file_path="$3"

    if [ "$INIT_ZDM_PROXY_CONFIGURATION_FILE" = "false" ]
    then
        echo -n > "$config_file_path"
        INIT_ZDM_PROXY_CONFIGURATION_FILE="true"
    fi

    config_name="$(tr "[:lower:]" "[:upper:]" <<<"$1")"
    if ! grep -q "$config_name" "$config_file_path"
    then
        echo "$config_name=$config_value" >> "$config_file_path"
    else
        sed -i "s,^$config_name=.*,$config_name=$config_value,g" "$config_file_path"
    fi
}

get_connection_type() {
    local host_type="$1"

    eval "echo \$ZDM_$(tr "[:lower:]" "[:upper:]" <<<"$host_type")_CONNECTION_TYPE"
}

to_upper() {
    tr "[:lower:]" "[:upper:]" <<<"$1"
}

get_host_connection_information() {
    # 1 - host type to search for in file
    # 2 - name of array to store entries found
    local host_type="$1"
    local host_info_rtn="$2"
    local host_info=()

    while [ ! -f "$SERVICE_HOSTS_FILE" ]
    do
        echo "Waiting for $SERVICE_HOSTS_FILE to be created, trying again in 20s"
        sleep 20
    done

    mapfile -t host_info < <(grep "$host_type" "$SERVICE_HOSTS_FILE")
    while [ ${#host_info[*]} -eq 0 ]
    do
        echo "no '$host_type' hosts found in $SERVICE_HOSTS_FILE, trying again in 20s"
        sleep 20
        mapfile -t host_info < <(grep "$host_type" "$SERVICE_HOSTS_FILE")
    done

    echo "Found '$host_type' hosts:"
    for host_info_i in ${host_info[*]}
    do
        echo " - ${host_info_i//:*/}: ${host_info_i//*:/}"
    done
    eval "$host_info_rtn=(${host_info[*]})"
}

set_cassandra_connection_information() {
    local host_type="$1"
    shift
    local connection_info=("$@")
    local contact_points=""

    contact_points="$(get_env_value "zdm_${host_type}_contact_points")"
    if [ -z "$contact_points" ]
    then
        contact_points="$(tr -s ' ' ',' <<<"${connection_info[*]/*:}")"
        set_env_value "zdm_${host_type}_contact_points" "$contact_points"
    fi

    if [ -z "$(get_env_value "zdm_${host_type}_port")" ]
    then
        # Use the default port if no value is specified
        set_env_value "zdm_${host_type}_port" "$(get_env_value "zdm_${host_type}_port_default")"
    fi
}

set_astra_connection_information() {
    local host_type="$1"
    shift
    local connection_info=("$@")
    # we need either a secure connect bundle path OR an astra db name and astra token
    local astra_scb_path=""
    local astra_scb_download_dir="/etc/zdmproxy"
    local astra_db_name=""
    local astra_init_token_path=""

    astra_scb_path=$(get_env_value "zdm_${host_type}_secure_connect_bundle_path")
    astra_db_name=$(get_env_value "zdm_${host_type}_astra_db_name")

    if [ -z "$astra_db_name" ]
    then
        astra_db_name="${connection_info[0]/*:}"
        set_env_value "zdm_${host_type}_astra_db_name" "$astra_db_name"
    fi

    if [ -z "$astra_scb_path" ]
    then
        mkdir -p "$astra_scb_download_dir"
        astra_init_token_path="$(get_env_value "zdm_${host_type}_init_token_file_path")"
        astra_scb_path=$(
            download_astra_secure_connect_bundle "$astra_db_name" "$astra_init_token_path" "$astra_scb_download_dir"
        )
        set_env_value "zdm_${host_type}_secure_connect_bundle_path" "$astra_scb_path"
    fi
}

set_host_connection_information() {
    local host_type_list=("origin" "target")
    local host_connection_type=""
    local host_connection_info=()

    set_env_value "zdm_proxy_listen_address" "$HOST_IP_ADDRESS"
    set_env_value "zdm_proxy_listen_port" "$ZDM_PROXY_LISTEN_PORT_DEFAULT"

    for host_type in ${host_type_list[*]}
    do
        host_connection_type="$(get_connection_type "$host_type")"
        host_connection_info=()
        get_host_connection_information "$host_type" "host_connection_info"

        if [ "$host_connection_type" = "cassandra" ]
        then
            set_cassandra_connection_information "$host_type" "${host_connection_info[*]}"
        elif [ "$host_connection_type" = "astra" ]
        then
            set_astra_connection_information "$host_type" "${host_connection_info[*]}"
        fi
    done
}

set_credential_information() {
    local host_type_list=("origin" "target")
    local error_msg=()
    for host_type in ${host_type_list[*]}
    do
        if [ -z "$(get_env_value "zdm_${host_type}_username")" ] || \
            [ -z "$(get_env_value "zdm_${host_type}_password")" ]
        then
            db_credentials_file_path="$(get_env_value "zdm_${host_type}_db_credentials_file_path")"
            if [ -n "$db_credentials_file_path" ]
            then
                while [ ! -f "$db_credentials_file_path" ]
                do
                    echo "Waiting for $db_credentials_file_path to be created, trying again in 20s"
                    sleep 20
                done

                set_env_value "zdm_${host_type}_username" "$(cut -d':' -f1 < "$db_credentials_file_path")"
                set_env_value "zdm_${host_type}_password" "$(cut -d':' -f2 < "$db_credentials_file_path")"
            else
                error_msg=(
                    "The '$(to_upper "zdm_${host_type}_db_credentials_file_path")', or the"
                    "'$(to_upper "zdm_${host_type}_username")' and '$(to_upper "zdm_${host_type}_password")'"
                    "environment variables need to contain a non-empty value.")
                break
            fi
        fi
    done

    if [ ${#error_msg[*]} -gt 0 ]
    then
        error_abort_deployment "${error_msg[*]}"
    fi
}

publish_env_value() {
    local env_name="$1"
    local env_value=""

    env_value=$(get_env_value "$env_name")
    if [ -n "$ZDM_PROXY_PUBLISH_CONFIGURATION_DIR" ]
    then
        write_env_value "$env_name" "$env_value" "${ZDM_PROXY_PUBLISH_CONFIGURATION_DIR}/${SERVICE_NAME}.conf"
    else
        export_env_value "$env_name" "$env_value"
    fi
}

publish_zdm_proxy_configuration() {
    local connection_type=""
    local error_msg=()

    publish_env_value "zdm_proxy_listen_address"
    publish_env_value "zdm_proxy_listen_port"

    host_type_list=("origin" "target")
    for host_type in ${host_type_list[*]}
    do
        publish_env_value "zdm_${host_type}_username"
        publish_env_value "zdm_${host_type}_password"

        connection_type="$(get_connection_type "$host_type")"
        if [ "$connection_type" = "cassandra" ]
        then
            if [ -n "$(get_env_value "zdm_${host_type}_contact_points")" ] && \
                [ -n "$(get_env_value "zdm_${host_type}_port")" ]
            then
                publish_env_value "zdm_${host_type}_contact_points"
                publish_env_value "zdm_${host_type}_port"
            else
                error_msg=(
                    "The '$(to_upper "zdm_${host_type}_contact_points")' and '$(to_upper "zdm_${host_type}_port")'"
                    "environment variables need to contain a value when the"
                    "'$(to_upper "zdm_${host_type}_connection_type")' environment variable is set to 'cassandra'.")
                break
            fi
        elif [ "$connection_type" = "astra" ]
        then
            if [ -n "$(get_env_value "zdm_${host_type}_secure_connect_bundle_path")" ]
            then
                publish_env_value "zdm_${host_type}_secure_connect_bundle_path"
            else
                error_msg=(
                    "The '$(to_upper "zdm_${host_type}_secure_connect_bundle_path")' environment variable needs to"
                    "contain a value when the '$(to_upper "zdm_${host_type}_connection_type")' environment variable"
                    " is set to 'astra'.")
                break
            fi
        fi
    done

    if [ ${#error_msg[*]} -gt 0 ]
    then
        error_abort_deployment "${error_msg[*]}"
    fi
}

service_start() {
    echo "Starting ZDM proxy"
    zdm-proxy &
    SERVICE_PID="$!"
}

service_stop() {
    echo "Stopping ZDM proxy"
    kill -SIGTERM "$SERVICE_PID"
}

service_restart() {
    while ! mv "$SERVICE_RESTART_LOCK_FREE" "$SERVICE_RESTART_LOCK_ACQUIRED" > /dev/null 2>&1
    do
        wait_time="$(shuf -i 1-30 -n 1)"
        echo "Unable to get lock to restart ZDM proxy, trying again in ${wait_time}s"
        sleep "$wait_time"
    done

    service_stop
    sleep 3
    service_start

    mv "$SERVICE_RESTART_LOCK_ACQUIRED" "$SERVICE_RESTART_LOCK_FREE"
}

watch_configuration_update_file() {
    touch "$ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH"
    if [ ! -f "$SERVICE_RESTART_LOCK_FREE" ] && [ ! -f "$SERVICE_RESTART_LOCK_ACQUIRED" ]
    then
        touch "$SERVICE_RESTART_LOCK_FREE"
    fi

    echo "Watching '$ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH' for any configuration changes"

    while true
    do
        sleep 20

        local env_value=""
        local config_name=""
        local config_value=""
        local config_changes=()

        while IFS= read -r name_value
        do
            config_name=${name_value//=*/}
            config_value=${name_value//*=/}

            env_value=$(get_env_value "$config_name")

            if [ "$env_value" != "$config_value" ]
            then
                config_changes+=("$name_value")
            fi
        done < "$ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH"

        if [ ${#config_changes[*]} -gt 0 ]
        then
            echo "Found new configuration values in '$ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH'; updating environment"
            for name_value in ${config_changes[*]}
            do
                config_name="${name_value//=*/}"
                config_value="${name_value//*=/}"
                set_env_value "$config_name" "$config_value"
                publish_env_value "$config_name"
            done
            service_restart
        fi
    done
}

#--- main execution ----------------------------------------------------------------------------------------------------

export INIT_ZDM_PROXY_CONFIGURATION_FILE="false"
export HOST_IP_ADDRESS="$(hostname -i)"
export SERVICE_PID=""
export SERVICE_RESTART_LOCK_FREE="${SERVICE_RUN_SHARE_DIR}/.zdm_restart_lock.free"
export SERVICE_RESTART_LOCK_ACQUIRED="${SERVICE_RUN_SHARE_DIR}/.zdm_restart_lock.acquired"

publish-connection-information "$HOST_IP_ADDRESS"

echo "Setting connection information"
set_host_connection_information

echo "Setting credential information"
set_credential_information

echo "Publishing configuration"
publish_zdm_proxy_configuration

if [ -z "$ZDM_PROXY_PUBLISH_CONFIGURATION_DIR" ]
then
    service_start
    if [ -n "$ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH" ]
    then
        watch_configuration_update_file &
    fi
fi

tail -F /dev/null # keeps container running