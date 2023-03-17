FROM baseservice:latest AS basebuild

FROM datastax/cql-proxy:v0.1.4 AS cqlproxybuilder

FROM ubuntu:20.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -y install \
        ca-certificates \
        unzip \
        jq \
        curl

RUN mkdir -p /opt/cql-proxy/
COPY cqlproxy-entrypoint.sh /usr/local/bin/
COPY --from=cqlproxybuilder /cql-proxy /opt/cql-proxy/
COPY --from=basebuild /publish-connection-information /usr/local/bin/
RUN chmod 755 \
      /usr/local/bin/cqlproxy-entrypoint.sh \
      /opt/cql-proxy/cql-proxy \
      /usr/local/bin/publish-connection-information && \
    ln -s /opt/cql-proxy/cql-proxy /usr/local/bin/cql-proxy

ENV SERVICE_RUN_SHARE_DIR /run/share
ENV SERVICE_HOSTS_FILE ${SERVICE_RUN_SHARE_DIR}/hosts

ENV DATABASE_SERVICE ""
ENV DATABASE_CONNECTION_TYPE ""

ENV ASTRA_DATABASE_ID ""
ENV ASTRA_TOKEN ""

EXPOSE 9042

ENTRYPOINT ["cqlproxy-entrypoint.sh"]
CMD [""]