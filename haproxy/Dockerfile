FROM golang:latest AS dataplaneapi-builder

ENV DATAPLANE_MINOR 2.7.5
ENV DATAPLANE_URL https://github.com/haproxytech/dataplaneapi.git

RUN git clone "${DATAPLANE_URL}" "${GOPATH}/src/github.com/haproxytech/dataplaneapi"
RUN cd "${GOPATH}/src/github.com/haproxytech/dataplaneapi" && \
    git checkout "v${DATAPLANE_MINOR}" && \
    make build && cp build/dataplaneapi /dataplaneapi

FROM debian:bullseye-slim AS openssl-builder

ENV OPENSSL_SHA256 4e23619f73688144f2cd808e9567504c3bf10cb67ad9551280530fd54ca913e1
ENV OPENSSL_URL https://github.com/quictls/openssl/archive/refs/tags/OpenSSL_1_1_1t-quic1.tar.gz

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential ca-certificates curl && \
    curl -sfSL "${OPENSSL_URL}" -o openssl.tar.gz && \
    mkdir -p /tmp/openssl && \
    tar -xzf openssl.tar.gz -C /tmp/openssl --strip-components=1 && \
    rm -f openssl.tar.gz && \
    cd /tmp/openssl && \
    ./config --libdir=lib --prefix=/opt/quictls && \
    make -j $(nproc) && \
    make install && \
    rm -rf /tmp/openssl

FROM debian:bullseye-slim

MAINTAINER Dinko Korunic <dkorunic@haproxy.com>

LABEL Name HAProxy
LABEL Release Community Edition
LABEL Vendor HAProxy
LABEL Version 2.8.0
LABEL RUN /usr/bin/docker -d IMAGE

ENV HAPROXY_BRANCH 2.8
ENV HAPROXY_MINOR 2.8.0
ENV HAPROXY_SHA256 61cdafb5db7e9174d0757b8e4bcde938352306fb7cc8ff2b5f55c26dd48a6cf7
ENV HAPROXY_SRC_URL http://www.haproxy.org/download

ENV HAPROXY_UID haproxy
ENV HAPROXY_GID haproxy

ENV DEBIAN_FRONTEND noninteractive

COPY --from=dataplaneapi-builder /dataplaneapi /usr/local/bin/dataplaneapi
COPY --from=openssl-builder /opt/quictls /opt/quictls

RUN apt-get update && \
    apt-get install -y --no-install-recommends procps zlib1g "libpcre2-*" liblua5.3-0 libatomic1 tar curl socat ca-certificates && \
    apt-get install -y --no-install-recommends gcc make libc6-dev libpcre2-dev zlib1g-dev liblua5.3-dev && \
    curl -sfSL "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/src/haproxy-${HAPROXY_MINOR}.tar.gz" -o haproxy.tar.gz && \
    echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c - && \
    groupadd "$HAPROXY_GID" && \
    useradd -g "$HAPROXY_GID" "$HAPROXY_UID" && \
    mkdir -p /tmp/haproxy && \
    tar -xzf haproxy.tar.gz -C /tmp/haproxy --strip-components=1 && \
    rm -f haproxy.tar.gz && \
    make -C /tmp/haproxy -j"$(nproc)" TARGET=linux-glibc CPU=generic USE_PCRE2=1 USE_PCRE2_JIT=1 USE_OPENSSL=1 \
                            USE_TFO=1 USE_LINUX_TPROXY=1 USE_LUA=1 USE_GETADDRINFO=1 \
                            USE_PROMEX=1 USE_SLZ=1 \
                            SSL_INC=/opt/quictls/include SSL_LIB=/opt/quictls/lib USE_QUIC=1 \
                            LDFLAGS="-L/opt/quictls/lib -Wl,-rpath,/opt/quictls/lib" \
                            all && \
    make -C /tmp/haproxy TARGET=linux-glibc install-bin install-man && \
    ln -s /usr/local/sbin/haproxy /usr/sbin/haproxy && \
    mkdir -p /var/lib/haproxy && \
    chown "$HAPROXY_UID:$HAPROXY_GID" /var/lib/haproxy && \
    mkdir -p /usr/local/etc/haproxy && \
    ln -s /usr/local/etc/haproxy /etc/haproxy && \
    cp -R /tmp/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors && \
    rm -rf /tmp/haproxy && \
    apt-get purge -y --auto-remove gcc make libc6-dev libpcre2-dev zlib1g-dev liblua5.3-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    chmod +x /usr/local/bin/dataplaneapi && \
    ln -s /usr/local/bin/dataplaneapi /usr/bin/dataplaneapi && \
    touch /usr/local/etc/haproxy/dataplaneapi.hcl && \
    chown "$HAPROXY_UID:$HAPROXY_GID" /usr/local/etc/haproxy/dataplaneapi.hcl && \
    echo "/opt/quictls/lib" > /etc/ld.so.conf.d/quictls.conf && \
    ldconfig

STOPSIGNAL SIGUSR1

ADD haproxy/docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh / # backwards compat
RUN apt update && apt install -y git lua5.3 liblua5.3-dev argon2 libargon2-dev luarocks
RUN git config --global url."https://".insteadOf git://
RUN luarocks install argon2

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/etc/haproxy/haproxy.cfg"]
