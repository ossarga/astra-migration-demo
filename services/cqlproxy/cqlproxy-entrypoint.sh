#!/bin/bash

get_env_value() {
    # 1 - environment variable name
    eval "echo \$$(tr "[:lower:]" "[:upper:]" <<<"$1")"
}

set_env_value() {
    # 1 - environment variable name
    # 2 - value to set the environment variable to
    eval "export $(tr "[:lower:]" "[:upper:]" <<<"$1")=$2"
}

check_for_file() {
    # 1 - file name to look for
    local file_path="$1"
    while [ ! -f "${file_path}" ]
    do
        echo "no file named '$file_path' found, trying again in 20s"
        sleep 20
    done
}

configure_astra_connection() {
    local astra_database_info=""
    local astra_database_id=""
    local astra_token=""
    local host_info=""
    local scb_file=""
    local token_file=""
    local ip_address=""

    while ! astra_database_info=$(grep "$database_service" "$SERVICE_HOSTS_FILE")
    do
        echo "no '$database_service' entry found in servicehosts file, trying again in 20s"
        sleep 20
    done

    scb_file="${SERVICE_RUN_SHARE_DIR}/${database_service}_scb_${astra_database_info//*:/}.zip"

    echo "looking for 'secure connection bundle'"
    check_for_file "$scb_file"

    mkdir -p /tmp/scb_files
    unzip "$scb_file" -d /tmp/scb_files

    host_info=$(jq -r '.host' /tmp/scb_files/config.json)
    astra_database_id=$(sed 's,\([a-f0-9\-]*\)\-.*,\1,g' <<<$host_info)
    rm -fr /tmp/scb_files

    token_file="${SERVICE_RUN_SHARE_DIR}/${database_service}_client_token"

    echo "looking for 'token file'"
    check_for_file "$token_file"

    astra_token="$(cat "$token_file")"

    set_env_value "astra_database_id" "$astra_database_id"
    set_env_value "astra_token" "$astra_token"
    set_env_value "bind" "${ip_address}:9042"
}


#--- main execution ----------------------------------------------------------------------------------------------------

if [ -z "$DATABASE_SERVICE" ] || [ -z "$DATABASE_CONNECTION_TYPE" ]
then
    echo "ERROR: A value must be set for both 'DATABASE_SERVICE' and 'DATABASE_CONNECTION_TYPE' environment variable."
    echo "Aborting CQLH Proxy deployment!"
    tail -F /dev/null # keeps container running
fi

ip_address="$(hostname -i)"

database_service=$(tr "[:upper:]" "[:lower:]" <<<"$(get_env_value "database_service")")
database_connection_type=$(get_env_value "database_connection_type")

if [ "$database_connection_type" = "astra" ]
then
    echo "database connection is '$database_connection_type'"
    configure_astra_connection
fi

publish-connection-information "$ip_address"

cql-proxy

echo "Ready"
tail -F /dev/null # keeps container running