FROM baseservice:latest AS basebuild

FROM ubuntu:20.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -y install \
        curl \
        unzip \
        jq \
        python3

RUN mkdir -p /astra-cli-install/ && \
    curl https://dtsx.io/get-astra-cli --location --output /astra-cli-install/get-astra-cli && \
    chmod 755 /astra-cli-install/get-astra-cli && \
    sed -i 's,^clear,,g' /astra-cli-install/get-astra-cli && \
    sed -i 's,^tput\ init,,g' /astra-cli-install/get-astra-cli && \
    /astra-cli-install/get-astra-cli

RUN curl https://downloads.datastax.com/enterprise/cqlsh-astra.tar.gz --location --output /root/cqlsh-astra.tar.gz && \
    tar xzf /root/cqlsh-astra.tar.gz -C /root/.astra/

RUN ln -s /usr/bin/python3 /usr/local/bin/python && \
    ln -s /root/.astra/cli/astra /usr/local/bin/astra && \
    ln -s /root/.astra/cqlsh-astra/bin/cqlsh /usr/local/bin/cqlsh-astra

RUN mkdir -p /etc/astra/templates
COPY config/schema_demo.cql /etc/astra/
COPY config/role_policies_template.json /etc/astra/templates/

ENV REVOKE_TOKEN_IF_EXISTS ""
ENV ASTRA_ADMIN_TOKEN ""
ENV ASTRA_ORG_ID ""
ENV ASTRA_DB_ID ""
ENV ASTRA_DB_NAME ""
ENV ASTRA_KEYSPACE_NAME "demo_keyspace"
ENV ASTRA_TABLE_NAME "demo_table"

ENV SCHEMA_DEMO_CQL /etc/astra/schema_demo.cql
ENV ROLE_POLICIES_TEMPLATE /etc/astra/templates/role_policies_template.json

ENV SERVICE_RUN_SHARE_DIR /run/share
ENV SERVICE_HOSTS_FILE ${SERVICE_RUN_SHARE_DIR}/hosts

ENV ASTRA_API_URL https://api.astra.datastax.com

COPY target-astra-entrypoint.sh /usr/local/bin/
COPY --from=basebuild /publish-connection-information /usr/local/bin/
RUN chmod 755 /usr/local/bin/target-astra-entrypoint.sh /usr/local/bin/publish-connection-information

ENTRYPOINT ["target-astra-entrypoint.sh"]
CMD [""]