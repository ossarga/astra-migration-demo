#!/bin/bash

RETRY_SLEEP_TIME=30

get_db_property() {
    # 1 - database property
    astra db get "$ASTRA_DB_NAME" --key "$1"
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

    echo "Running: astra db cqlsh $ASTRA_DB_NAM -${input_opt} $1"
    astra db cqlsh "$ASTRA_DB_NAME" "-${input_opt}" "$1"
}

execute_cql_statement_supress_stderr() {
    # 1 - CQL statement
    execute_cql_statement "$1" 2>/dev/null
}

create_schema() {
    echo "Applying schema"
    execute_cql_statement "$SCHEMA_DEMO_CQL"
    execute_cql_statement "DESCRIBE KEYSPACE $ASTRA_KEYSPACE_NAME;"
}

call_api_resource() {
    # 1 - request type (GET, POST, DELETE)
    # 2 - resource path
    # 3 - json string or file payload
    local request_type="$1"
    local resource_path="$2"
    local payload_arg="$3"

    local curl_cmd=(
        "curl"
        "-s"
        "--header \"Authorization: Bearer $ASTRA_ADMIN_TOKEN\""
        "--header \"Content-Type: application/json\""
        "--request $request_type"
    )

    if [ -n "$payload_arg" ]
    then
        if [ -f "$payload_arg" ]
        then
            payload_arg="--data @$payload_arg"
        else
            payload_arg="--data '$payload_arg'"
        fi
        curl_cmd+=("$payload_arg")
    fi

    curl_cmd+=("${ASTRA_API_URL}/${resource_path}")

    eval "${curl_cmd[*]}"
}

create_role() {
    # 1 - type of the role to create
    # 2 - the variable name to return the role id
    # 3 - the variable name to return the role name
    local role_type="$1"
    local astra_policy_resource_components=()
    local resource_vars=""
    local role_id_rtn=""
    local role_name_rtn=""
    local role_info=$(astra role list --output csv | grep -i "$role_type")

    if [ -z "$role_info" ]
    then
        echo "Creating $role_type role"
        rm -f /tmp/role.json
        jq ".${role_type}" "${ROLE_POLICIES_TEMPLATE}" > /tmp/role.json
        OLD_IFS="$IFS"
        IFS=":"
        astra_policy_resource_components+=($(jq -r '. | .policy | .resources | .[]' /tmp/role.json))
        IFS="$OLD_IFS"
        resource_vars=($(tr -s ' ' '\n' <<<"${astra_policy_resource_components[*]}" | grep "##ASTRA_" | sort -u))

        for var_key in ${resource_vars[*]}
        do
            local var_name=$(tr -d '#' <<<"$var_key")
            local var_env_val=$(eval echo \$"$var_name")
            sed -i "s,$var_key,$var_env_val,g" /tmp/role.json
        done

        local api_response=$(call_api_resource "POST" "v2/organizations/roles" "/tmp/role.json")
        if ! jq empty <<<"$api_response"
        then
            echo "ERROR: Failed to create $role_type; $api_response"
            return 1
        fi

        role_id_rtn=$(jq -r '.id' <<<"$api_response")
        role_name_rtn=$(jq -r '.name' <<<"$api_response")
    else
        echo "Found $role_type role"
        role_id_rtn=$(cut -d',' -f1 <<<"$role_info")
        role_name_rtn=$(cut -d',' -f2 <<<"$role_info")
    fi

    eval "$2=$role_id_rtn"
    eval "$3=\"$role_name_rtn\""
}

create_role_token() {
    # 1 - role type
    # 2 - role id
    # 3 - role name
    local role_type="$1"
    local role_id="$2"
    local role_name="$3"

    if [ "$REVOKE_TOKEN_IF_EXISTS" = "true" ]
    then
        local api_response=$(call_api_resource "GET" "v2/clientIdSecrets")
        OLD_IFS="$IFS"
        IFS=";"
        local client_roles_list=($(
            jq -r -c '.[][] | .clientId, .roles' <<<"$api_response" | \
            tr -d '\n' | \
            tr -d '"' | \
            tr -s '[' ':' | \
            tr -s ']' ';'))
        IFS="$OLD_IFS"

        for client_roles in ${client_roles_list[*]}
        do
            if [ "${client_roles/*:}" = "$role_id" ]
            then
                echo "Found token '${client_roles/:*}' using role '$role_name'; revoking"
                api_response=$(call_api_resource "DELETE" "v2/clientIdSecrets/${client_roles/:*}")
                break
            fi
        done
    fi

    echo "Creating new token for role '$role_name'"
    api_response=$(call_api_resource "POST" "v2/clientIdSecrets" "{ \"roles\": [ \"$role_id\" ] }")
    if ! jq empty <<<"$api_response"
    then
        echo "ERROR: Failed to create token for '$role_name'; api_response"
        return 1
    fi

    local client_id=$(jq -r '.clientId' <<<"$api_response")
    local secret=$(jq -r '.secret' <<<"$api_response")
    local token=$(jq -r '.token' <<<"$api_response")

    # Save credentials and token to share
    echo "${client_id}:${secret}" > "${SERVICE_RUN_SHARE_DIR}/target_${role_type}_credentials"
    echo "${token}" > "${SERVICE_RUN_SHARE_DIR}/target_${role_type}_token"
}

#--- main execution ----------------------------------------------------------------------------------------------------

if [ -z "$ASTRA_ADMIN_TOKEN" ]
then
    echo "ERROR: no astra token defined in 'ASTRA_ADMIN_TOKEN' environment variable"
    tail -F /dev/null
fi

rm -fv "${SERVICE_RUN_SHARE_DIR}/target_client_credentials"
rm -fv "${SERVICE_RUN_SHARE_DIR}/target_client_token"
rm -fv "${SERVICE_RUN_SHARE_DIR}/target_zdmproxy_credentials"
rm -fv "${SERVICE_RUN_SHARE_DIR}/target_zdmproxy_token"

echo
echo "Running: astra setup"
astra setup <<<"$ASTRA_ADMIN_TOKEN"

echo
echo "Running: astra --version"
astra --version

echo
echo "Running: astra config list"
astra config list

echo
echo "Running: astra db create $ASTRA_DB_NAME --keyspace $ASTRA_KEYSPACE_NAME --if-not-exist --wait"
astra db create "$ASTRA_DB_NAME" --keyspace "$ASTRA_KEYSPACE_NAME" --if-not-exist --wait

if [ "$(get_db_property "status")" = "HIBERNATED" ]
then
    echo "Astra '$ASTRA_DB_NAME' is asleep, waking it up ..."
    astra db resume "$ASTRA_DB_NAME"
fi

echo
echo "Running: astra db list"
astra db list

ASTRA_ORG_ID=$(astra org id)
ASTRA_DB_ID=$(get_db_property "id")

while ! execute_cql_statement_supress_stderr "quit;"
do
    echo "cqlsh interface unavailable; waiting $RETRY_SLEEP_TIME seconds before trying again"
    sleep $RETRY_SLEEP_TIME
done

create_schema

role_type_list=()
mapfile -t role_type_list < <(jq -r 'keys | .[]' "${ROLE_POLICIES_TEMPLATE}")
for role_type in ${role_type_list[*]}
do
    role_id=""
    role_name=""
    create_role "$role_type" "role_id" "role_name"
    create_role_token "$role_type" "$role_id" "$role_name"
done

scb_path="${SERVICE_RUN_SHARE_DIR}/target_scb_${ASTRA_DB_NAME}.zip"
if [ ! -f "$scb_path" ]
then
    echo "Running: astra db download-scb ${ASTRA_DB_NAME}"
    astra db download-scb "${ASTRA_DB_NAME}" -f "$scb_path"
else
    echo "Found secure connection bundle in $scb_path"
fi

publish-connection-information "$ASTRA_DB_NAME"

echo "Done!"

tail -F /dev/null # keeps container running