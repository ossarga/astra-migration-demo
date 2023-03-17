FROM baseservice:latest AS baseimage

FROM nosqlbench/nosqlbench:4.17.32

ENV ETC_NOSQLBENCH /etc/nosql-bench

RUN apt-get update && \
    DEBIAN_FRONTEND="noninteractive" apt-get -y install \
        jq \
        curl \
        unzip \
        python3 \
        python3-pip

RUN curl https://downloads.datastax.com/enterprise/cqlsh-astra.tar.gz --location --output /root/cqlsh-astra.tar.gz && \
    tar xzf /root/cqlsh-astra.tar.gz -C /opt/ && \
    ln -s /opt/cqlsh-astra/bin/cqlsh /usr/local/bin/cqlsh && \
    rm /root/cqlsh-astra.tar.gz

COPY client-entrypoint.sh bin/nosql-bench /usr/local/bin/
COPY --from=baseimage /download_astra_secure_connect_bundle /usr/local/bin/
RUN chmod 755 \
      /usr/local/bin/download_astra_secure_connect_bundle \
      /usr/local/bin/client-entrypoint.sh \
      /usr/local/bin/nosql-bench

RUN mkdir -p ${ETC_NOSQLBENCH}/
COPY config/schema_*.cql ${ETC_NOSQLBENCH}/

ENV SERVICE_RUN_SHARE_DIR /run/share
ENV SERVICE_HOSTS_FILE ${SERVICE_RUN_SHARE_DIR}/hosts

# Options are: target (default), origin
ENV CLIENT_PRIMARY_CLUSTER_CREDENTIALS "target"
ENV CLIENT_USERNAME ""
ENV CLIENT_PASSWORD ""


ENV ORIGIN_CONNECTION_TYPE ""
ENV ORIGIN_ASTRA_DB_NAME ""
ENV ORIGIN_INIT_TOKEN_FILE_PATH ""
ENV ORIGIN_SECURE_CONNECT_BUNDLE_PATH ""

ENV ORIGIN_DB_CREDENTIALS_FILE_PATH ""
ENV ORIGIN_USERNAME ""
ENV ORIGIN_PASSWORD ""


ENV TARGET_CONNECTION_TYPE ""
ENV TARGET_ASTRA_DB_NAME ""
ENV TARGET_INIT_TOKEN_FILE_PATH ""
ENV TARGET_SECURE_CONNECT_BUNDLE_PATH ""

ENV TARGET_DB_CREDENTIALS_FILE_PATH ""
ENV TARGET_USERNAME ""
ENV TARGET_PASSWORD ""






ENTRYPOINT ["client-entrypoint.sh"]
CMD [""]