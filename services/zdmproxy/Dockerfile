FROM baseservice:latest AS baseimage

FROM datastax/zdm-proxy:latest AS zdmproxybuilder

FROM ubuntu:20.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -y install \
        jq \
        curl

RUN mkdir -p /opt/zdm-proxy/
COPY --from=baseimage /publish-connection-information /download_astra_secure_connect_bundle /usr/local/bin/
COPY --from=zdmproxybuilder /main /opt/zdm-proxy/
COPY zdmproxy-entrypoint.sh /usr/local/bin/
RUN chmod 755 \
      /usr/local/bin/publish-connection-information \
      /usr/local/bin/download_astra_secure_connect_bundle  \
      /opt/zdm-proxy/main \
      /usr/local/bin/zdmproxy-entrypoint.sh && \
    ln -s /opt/zdm-proxy/main /usr/local/bin/zdm-proxy

ENV SERVICE_NAME ""
ENV SERVICE_RUN_SHARE_DIR /run/share
ENV SERVICE_HOSTS_FILE ${SERVICE_RUN_SHARE_DIR}/hosts

# Leave ZDM_PUBLISH_CONFIGURATION_DIR blank to start ZDM proxy. Otherwise this will publish the configuration to a
#   file without starting ZDM proxy.
ENV ZDM_PROXY_PUBLISH_CONFIGURATION_DIR ""
ENV ZDM_PROXY_CONFIGURATION_UPDATE_FILE_PATH ""
ENV ZDM_PROXY_LISTEN_PORT_DEFAULT 9042

ENV ZDM_ORIGIN_CONNECTION_TYPE ""
ENV ZDM_ORIGIN_INIT_TOKEN_FILE_PATH ""
ENV ZDM_ORIGIN_DB_CREDENTIALS_FILE_PATH ""
ENV ZDM_ORIGIN_PORT_DEFAULT 9042

ENV ZDM_TARGET_CONNECTION_TYPE ""
ENV ZDM_TARGET_INIT_TOKEN_FILE_PATH ""
ENV ZDM_TARGET_DB_CREDENTIALS_FILE_PATH ""
ENV ZDM_TARGET_PORT_DEFAULT 9042

ENV ZDM_LOG_LEVEL "WARN"

EXPOSE 9042

ENTRYPOINT ["zdmproxy-entrypoint.sh"]
CMD [""]