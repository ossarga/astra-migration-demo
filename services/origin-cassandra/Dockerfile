FROM baseservice:latest AS basebuild

FROM cassandra:3.11

RUN apt-get update && \
    apt-get -y install \
        curl \
        jq

COPY config/schema_demo.cql config/role_policies.json /etc/cassandra/
COPY cassandra-entrypoint-wrapper.sh /usr/local/bin/
COPY --from=basebuild /publish-connection-information /usr/local/bin/
RUN chmod 755 /usr/local/bin/cassandra-entrypoint-wrapper.sh /usr/local/bin/publish-connection-information

ENV CASSANDRA_YAML /etc/cassandra/cassandra.yaml
ENV SCHEMA_DEMO_CQL /etc/cassandra/schema_demo.cql
ENV ROLE_POLICIES /etc/cassandra/role_policies.json

ENV SERVICE_RUN_SHARE_DIR /run/share
ENV SERVICE_HOSTS_FILE ${SERVICE_RUN_SHARE_DIR}/hosts

ENV ADMIN_ROLE_NAME ""
ENV ADMIN_ROLE_PASSWORD ""
ENV CLIENT_ROLE_NAME ""
ENV CLIENT_ROLE_PASSWORD ""
ENV ZDMPROXY_ROLE_NAME ""
ENV ZDMPROXY_ROLE_PASSWORD ""

ENTRYPOINT ["cassandra-entrypoint-wrapper.sh"]