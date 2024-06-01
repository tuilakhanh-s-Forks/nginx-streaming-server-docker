ARG FFMPEG_VERSION=7.0
ARG NGINX_VERSION=1.26.0
ARG NGINX_RTMP_VERSION=master
ARG NGINX_VOD_VERSION=1.33

##############################
# Build the NGINX-build image.
FROM debian:bookworm-slim as nginx-build
ARG NGINX_VERSION
ARG NGINX_RTMP_VERSION
ARG NGINX_VOD_VERSION
ARG MAKEFLAGS="-j16"

# Build dependencies.
RUN apt-get update && apt-get install -y \
    gcc \
    make \
    ca-certificates \
    libpcre3 \
    libpcre3-dev \
    zlib1g \
    zlib1g-dev \
    openssl \
    libssl-dev \
    wget \
    xz-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

# Get nginx source.
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz

# Get nginx-http-flv module.
RUN wget https://github.com/winshining/nginx-http-flv-module/archive/${NGINX_RTMP_VERSION}.tar.gz && \
  tar zxf ${NGINX_RTMP_VERSION}.tar.gz && \
  rm ${NGINX_RTMP_VERSION}.tar.gz

# Get nginx-vod module.
RUN wget https://github.com/kaltura/nginx-vod-module/archive/${NGINX_VOD_VERSION}.tar.gz && \
  tar zxf ${NGINX_VOD_VERSION}.tar.gz && \
  rm ${NGINX_VOD_VERSION}.tar.gz

# Compile nginx with nginx-rtmp module.
WORKDIR /tmp/nginx-${NGINX_VERSION}
RUN \
  ./configure \
    --prefix=/usr/local/nginx \
    --add-module=/tmp/nginx-http-flv-module-${NGINX_RTMP_VERSION} \
    --add-module=/tmp/nginx-vod-module-${NGINX_VOD_VERSION} \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --pid-path=/var/run/nginx/nginx.pid \
    --lock-path=/var/lock/nginx/nginx.lock \
    --http-log-path=/var/log/nginx/access.log \
    --http-client-body-temp-path=/tmp/nginx-client-body \
    --with-threads \
    --with-file-aio \
    --with-http_ssl_module \
    --with-ipv6 \
    --with-debug \
    --with-http_stub_status_module \
    --with-cc-opt="-Wimplicit-fallthrough=0" && \
  make && \
  make install && \
  rm -rf /tmp/*


##########################
# Build go server
FROM golang:1.20-alpine as go-server
WORKDIR /app
COPY go-server/ .
RUN go build -o server main.go

##########################
# Build the release image.
FROM debian:bookworm-slim
ARG FFMPEG_VERSION

# Build dependencies.
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libpcre3 \
    zlib1g \
    openssl \
    libssl-dev \
    wget \
    xz-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN wget https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-${FFMPEG_VERSION}.tar.xz && \
    tar -xvf ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-${FFMPEG_VERSION}.tar.xz && \
    mv ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-${FFMPEG_VERSION}/bin/ffmpeg /usr/local/bin && \
    mv ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-${FFMPEG_VERSION}/bin/ffprobe /usr/local/bin && \
    rm -rf ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-${FFMPEG_VERSION} && \
    rm ffmpeg-n${FFMPEG_VERSION}-latest-linux64-gpl-${FFMPEG_VERSION}.tar.xz

WORKDIR /
RUN ffmpeg -version

COPY --from=nginx-build /usr/local/nginx /usr/local/nginx
COPY --from=nginx-build /etc/nginx /etc/nginx
COPY --from=go-server /app/server /usr/local/bin/server

# Add NGINX path, config and static files.
ENV PATH "${PATH}:/usr/local/nginx/sbin"
RUN mkdir /var/log/nginx && \
  mkdir /var/run/nginx && \
  mkdir /var/lock/nginx && \
  mkdir /tmp/nginx-client-body && \
  mkdir /www
  # mkdir /data/records/

COPY static /www/static

RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

COPY entrypoint.sh /

RUN chmod +x /entrypoint.sh

CMD ["chown" "-R" "nobody" "/data"]

ENTRYPOINT ["/entrypoint.sh"]