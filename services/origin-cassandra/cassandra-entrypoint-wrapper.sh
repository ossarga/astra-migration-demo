#!/bin/bash

CURRENT_ADMIN_ROLE_NAME="cassandra"
CURRENT_ADMIN_ROLE_PASSWORD="cassandra"

ALTER_ROLE_DDL="ALTER ROLE"
CREATE_ROLE_DDL="CREATE ROLE IF NOT EXISTS"

RETRY_SLEEP_TIME=30


get_env_value() {
    # 1 - environment variable name
    eval "echo \$$(tr "[:lower:]" "[:upper:]" <<<"$1")"
}

execute_cql_statement() {
    # 1 - CQL statement
    local  input_opt=""
    if [ -f "$1" ]
    then
        input_opt="f"
    else
        input_opt="e"
    fi

    cqlsh localhost -u "$CURRENT_ADMIN_ROLE_NAME" -p "$CURRENT_ADMIN_ROLE_PASSWORD" "-${input_opt}" "$1"
}

execute_cql_statement_supress_stderr() {
    execute_cql_statement "$1" 2>/dev/null
}

assemble_role_statement() {
    # 1 - action
    # 2 - user name
    # 3 - user password
    # 4 - is superuser
    # 5 - is login enabled
    local cql_role_statement="$1 $2 WITH PASSWORD = '$3' AND SUPERUSER = $4 AND LOGIN = $5;"
    execute_cql_statement "$cql_role_statement"
}

alter_role() {
    echo "Altering user '$1' with superuser=$3 and login=$4"
    # 1 - user name
    # 2 - user password
    # 3 - is superuser
    # 4 - is login enabled
    assemble_role_statement "$ALTER_ROLE_DDL" "$1" "$2" "$3" "$4"
}

create_role() {
    echo "Creating user '$1' with superuser=$3 and login=$4"
    # 1 - new user name
    # 2 - new user password
    # 3 - is superuser
    # 4 - is login enabled
    assemble_role_statement "$CREATE_ROLE_DDL" "$1" "$2" "$3" "$4"
}

grant_user_permission() {
    echo "Granting user '$1' with permissions $2 for resource $3"
    # 1 - user name
    # 2 - permissions
    # 3 - resource
    execute_cql_statement "GRANT $2 ON $3 TO $1;"
}

replace_super_user() {
    # 1 - new admin name
    # 2 - new admin password
    local old_admin_name="$CURRENT_ADMIN_ROLE_NAME"
    local old_admin_password="$CURRENT_ADMIN_ROLE_PASSWORD"
    local new_admin_name="$1"
    local new_admin_password="$2"

    echo "Replacing '$old_admin_name' user with '$new_admin_name'"
    create_role "$new_admin_name" "$new_admin_password" "true" "true"
    CURRENT_ADMIN_ROLE_NAME="$new_admin_name"
    CURRENT_ADMIN_ROLE_PASSWORD="$new_admin_password"
    alter_role "$old_admin_name" "$old_admin_password" "false" "false"
}

create_schema() {
    echo "Applying schema"
    execute_cql_statement "$SCHEMA_DEMO_CQL"
    execute_cql_statement "DESCRIBE SCHEMA;"
}

post_start_operations() {
    # Wait for CQLSH to be available before we perform operations on the user accounts

    while ! execute_cql_statement_supress_stderr "quit;"
    do
        echo "No RPC interface unavailable; waiting $RETRY_SLEEP_TIME seconds before trying again"
        sleep $RETRY_SLEEP_TIME
    done

    create_schema

    if [ -n "$ADMIN_ROLE_NAME" ] && [ -n "$ADMIN_ROLE_PASSWORD" ]
    then
        replace_super_user "$ADMIN_ROLE_NAME" "$ADMIN_ROLE_PASSWORD"
    fi

    local role_type_list=()
    mapfile -t role_type_list < <(jq -r 'keys | .[]' "${ROLE_POLICIES}")
    for role_type in ${role_type_list[*]}
    do
        local role_name=$(get_env_value "${role_type}_role_name")
        local role_password=$(get_env_value "${role_type}_role_password")

        if [ -n "$role_name" ] && [ -n "$role_password" ]
        then
            create_role "$role_name" "$role_password" "false" "true"

            local resource_name=$(jq -r ".${role_type}.policy.resource_name" "${ROLE_POLICIES}")
            for role_privilege in $(jq -r ".${role_type}.policy.privilege | .[]" "${ROLE_POLICIES}")
            do
                grant_user_permission "$role_name" "$role_privilege" "$resource_name"
            done

            # Save credentials to share
            echo "${role_name}:${role_password}" > "${SERVICE_RUN_SHARE_DIR}/origin_${role_type}_credentials"
        fi
    done

    publish-connection-information "$(hostname -i)"

    echo "Post start operations complete!"
}

set_configuration_values() {
    echo "Updating settings in $CASSANDRA_YAML"
    cassandra_env_config_values=($(env | grep "CASSANDRA_"))

    for env_var in ${cassandra_env_config_values[*]}
    do
        conf_key=$(cut -d'=' -f1 <<<"${env_var/*CASSANDRA_/}" | tr [:upper:] [:lower:])
        new_conf_val="${env_var/*=/}"
        old_conf_val=$(grep -e "^${conf_key}" "$CASSANDRA_YAML" | tr -d ' ' | cut -d':' -f2)

        if [ -n "$old_conf_val" ] && [ "$old_conf_val" != "$new_conf_val" ]
        then
            echo "Setting $conf_key=$new_conf_val"
            sed -i "s,^$conf_key\:[\ ]*\(.*\),$conf_key: $new_conf_val,g" "$CASSANDRA_YAML"
        fi
    done
}

#--- main execution ----------------------------------------------------------------------------------------------------

rm -fv "${SERVICE_RUN_SHARE_DIR}/origin_client_credentials"
rm -fv "${SERVICE_RUN_SHARE_DIR}/origin_zdmproxy_credentials"

set_configuration_values
sleep 5
post_start_operations &

exec docker-entrypoint.sh "$@"