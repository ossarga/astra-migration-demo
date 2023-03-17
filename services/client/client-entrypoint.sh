#!/bin/bash

DEMO_INSERT_DML="INSERT INTO demo_keyspace.demo_table (id, day_window, read_timestamp, value)"
DEMO_SELECT_DML="SELECT * FROM demo_keyspace.demo_table"

get_env_value() {
    # 1 - environment variable name
    eval "echo \$$(tr "[:lower:]" "[:upper:]" <<<"$1")"
}

set_env_value() {
    # 1 - environment variable name
    # 2 - value to set the environment variable to
    eval "$(tr "[:lower:]" "[:upper:]" <<<"$1")=$2"
}

get_db_connection_type() {
    local host_type="$1"

    if [ "$host_type" = "zdmproxy" ]
    then
        echo "cassandra"
    else
        get_env_value "${host_type}_connection_type"
    fi
}

get_host_info() {
    local host_type="$1"

    echo "Getting info for entry '$host_type'"

    while ! get_host_info_results=($(grep "$host_type" "$SERVICE_HOSTS_FILE"))
    do
        echo "no '$host_type' entry found in hostsfile, trying again in 20s"
        sleep 20
    done
}

get_credentials_args_for_cqlsh() {
    # 1 - host type
    local host_type="$1"
    local host_username=""
    local host_password=""

    if [ "$host_type" = "zdmproxy" ]
    then
        host_username=$(get_env_value "client_username")
        host_password=$(get_env_value "client_password")
    else
        host_username=$(get_env_value "${host_type}_username")
        host_password=$(get_env_value "${host_type}_password")
    fi

    echo "--username=$host_username --password=$host_password"
}

get_db_connection_info() {
    # 1 - host type
    local host_type="$1"
    local hosts_var_list_name="${host_type}_host_info_list"
    local num_hosts=$(eval "echo \${#${hosts_var_list_name}[*]}")
    local host_index=$(shuf  -i 0-$((num_hosts - 1)) -n 1)

    # For 'cassandra' this is an ip address; for 'astra' this is a database name
    eval "echo \${${hosts_var_list_name}[$host_index]//*:/}"
}

execute_cql_statement() {
    # 1 - host type
    # 2 - CQL statement or CQL file
    # 3 - connection info override (optional); either an ip address or astra database name
    local host_type="$1"
    local cql_statement="$2"
    local connection_info_override="$3"
    local connection_type=$(get_db_connection_type "$host_type")
    local connection_info="$(get_db_connection_info "$host_type")"
    local user_credentials="$(get_credentials_args_for_cqlsh "$host_type")"

    if [ -n "$connection_info_override" ]
    then
        connection_info="$connection_info_override"
    fi

    if [ -f "$cql_statement" ]
    then
        cql_statement="--file=$cql_statement"
    else
        cql_statement="--execute=\"$cql_statement\""
    fi

    if [ "$connection_type" = "astra" ]
    then
        connection_info="--secure-connect-bundle=$(get_env_value "${host_type}_secure_connect_bundle_path")"
    fi
    
    eval "cqlsh $connection_info $user_credentials $cql_statement --consistency-level=QUORUM"
}

configure_astra_connection() {
    local host_type="$1"
    shift
    local connection_info=("$@")
    # we need either a secure connect bundle path OR an astra db name and astra token
    local astra_scb_path=""
    local astra_scb_download_dir="/etc/client/"
    local astra_db_name=""
    local astra_init_token_path=""

    astra_db_name=$(get_env_value "${host_type}_astra_db_name")
    astra_scb_path=$(get_env_value "${host_type}_secure_connect_bundle_path")

    if [ -z "$astra_db_name" ]
    then
        astra_db_name="${connection_info[0]/*:}"
        set_env_value "${host_type}_astra_db_name" "$astra_db_name"
    fi

    if [ -z "$astra_scb_path" ]
    then
        mkdir -p "$astra_scb_download_dir"
        astra_init_token_path="$(get_env_value "${host_type}_init_token_file_path")"
        astra_scb_path=$(
            download_astra_secure_connect_bundle "$astra_db_name" "$astra_init_token_path" "$astra_scb_download_dir"
        )
        set_env_value "${host_type}_secure_connect_bundle_path" "$astra_scb_path"
    fi
}

check_connections() {
    # 1 - executing host type
    local host_type="$1"
    local connection_type=$(get_db_connection_type "$host_type")

    if [ "$connection_type" = "cassandra" ]
    then
        local user_credentials="$(get_credentials_args_for_cqlsh "$host_type")"
        local hosts_var_list_name="${host_type}_host_info_list"

        for host_ip in $(eval "echo \${${hosts_var_list_name}[*]//*:/}")
        do
            while ! execute_cql_statement "$host_type" "quit;" "$host_ip" > /dev/null 2>&1
            do
                echo "cqlsh not ready on $host_ip, trying again in 30s"
                sleep 30
                echo "retrying cqlsh connection on $1"
            done
        done
    fi
}

demo_get_day_window() {
    date +%Y%m%d
}

demo_insert_historical_data() {
    # $1 - executing host type
    local host_type="$1"
    local day_window=$(demo_get_day_window)
    local start_timestamp=$(date -d "$day_window" +%s)
    local cql_insert_dml_statements_file="/insert_dml.cql"

    rm -f "$cql_insert_dml_statements_file"

    for minute_value in $(seq 0 60 240)
    do
        read_timestamp_sec=$((start_timestamp + minute_value))
        echo "$DEMO_INSERT_DML VALUES (1, $day_window, ${read_timestamp_sec}000, $RANDOM);" >> $cql_insert_dml_statements_file
    done

    execute_cql_statement "$host_type" "$cql_insert_dml_statements_file"
}

demo_insert_live_data() {
    # 1 - executing host type
    # 2 - executing host name/ref
    local host_type="$1"
    local connection_info=$(get_db_connection_info "$host_type")
    local day_window=$(demo_get_day_window)
    local read_timestamp=$(date +%s000)
    local data_value=$RANDOM

    echo "Inserting data into $2 ($connection_info): day_window=$day_window read_timestamp=$read_timestamp value=$data_value"
    execute_cql_statement "$host_type" "$DEMO_INSERT_DML VALUES (1, $day_window, $read_timestamp, $data_value);"
}

demo_select_data() {
    # 1 - executing host type
    # 2 - executing host name/ref
    local host_type="$1"
    local connection_info=$(get_db_connection_info "$host_type")
    local day_window=$(demo_get_day_window)

    echo "Reading data from $2 ($connection_info): day_window=$day_window"
    execute_cql_statement "$host_type" "$DEMO_SELECT_DML WHERE id=1 AND day_window=$day_window;"
}

run_demo() {
    echo
    echo "===== Running ZDM Proxy Demo =============================="
#    echo "Adding historical data to Origin"
#
#    demo_insert_historical_data "origin" "Origin Database"
#    demo_select_data "origin" "Origin Database"
#
#    sleep 10
#
#    echo
#    echo "==========================================================="
    while true
    do
        echo
        demo_insert_live_data "zdmproxy" "ZDM Proxy"
        demo_select_data "zdmproxy" "ZDM Proxy"
#        echo
#        demo_select_data "origin" "Origin Database"
#        echo
#        demo_select_data "target" "Target Database"
        echo "==========================================================="
        sleep 60
    done
}

#--- main execution ----------------------------------------------------------------------------------------------------

while [ ! -f "$SERVICE_HOSTS_FILE" ]
do
    echo "Waiting for $SERVICE_HOSTS_FILE to be created, trying again in 20s"
    sleep 20
done

echo "Found $SERVICE_HOSTS_FILE, getting connection information"
host_type_list=("origin" "target" "zdmproxy")
for host_type in ${host_type_list[*]}
do
    get_host_info_results=()
    get_host_info "$host_type"

    hosts_var_list_name="${host_type}_host_info_list"
    eval "$hosts_var_list_name=(${get_host_info_results[*]})"

    if [ "$(get_db_connection_type "$host_type")" = "astra" ]
    then
        configure_astra_connection "$host_type" "${get_host_info_results[*]}"
    fi
done

echo "Getting database credentials"
host_type_list=("origin" "target")
for host_type in ${host_type_list[*]}
do
    if [ -z "$(get_env_value "${host_type}_username")" ] || [ -z "$(get_env_value "${host_type}_password")" ]
    then
        host_credentials_file=$(get_env_value "${host_type}_db_credentials_file_path")
        if [ -f "$host_credentials_file" ] && [ -n "$host_credentials_file" ]
        then
            set_env_value "${host_type}_username" "$(cut -d':' -f1 < "$host_credentials_file")"
            set_env_value "${host_type}_password" "$(cut -d':' -f2 < "$host_credentials_file")"
        else
            host_type_upper=$(tr "[:lower:]" "[:upper:]" <<<"$host_type")
            echo "ERROR: non-empty string credentials must be set in the '${host_type_upper}_USERNAME' and
                  '${host_type_upper}_PASSWORD' environment variables, or in the
                  'compose/share/${host_type}_client_credentials' file."
            echo "Aborting Client startup!"
            tail -F /dev/null # keeps container running
        fi
    fi
done

if [ -z "$CLIENT_USERNAME" ] || [ -z "$CLIENT_PASSWORD" ]
then
    if [ -z "$CLIENT_PRIMARY_CLUSTER_CREDENTIALS" ]
    then
        echo "ERROR: 'CLIENT_USERNAME' and 'CLIENT_PASSWORD', or 'CLIENT_PRIMARY_CLUSTER_CREDENTIALS' environment
              variables need to contain a non-empty value in order for the client to connect to the databases"
        echo "Aborting Client setup!"
        tail -F /dev/null # keeps container running
    else
        set_env_value "client_username" "$(get_env_value "${CLIENT_PRIMARY_CLUSTER_CREDENTIALS}_username")"
        set_env_value "client_password" "$(get_env_value "${CLIENT_PRIMARY_CLUSTER_CREDENTIALS}_password")"
    fi
fi

# Wait for clusters and proxy to be responsive
host_type_list=("origin" "target" "zdmproxy")
for host_type in ${host_type_list[*]}
do
    check_connections "$host_type"
done

run_demo

tail -F /dev/null # keeps container running