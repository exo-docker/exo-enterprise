# syntax=docker/dockerfile:1
#
# Dockerizing base image for eXo Platform hosting offer with:
#
# - eXo Platform

# Build:    docker build -t exoplatform/exo-enterprise .
#
# Run:      docker run -ti --rm --name=exo -p 80:8080 exoplatform/exo-enterprise
#           docker run -d --name=exo -p 80:8080 exoplatform/exo-enterprise

ARG BASE_IMAGE=exoplatform/jdk:openjdk-21-ubuntu-2604

# Fetch & unpack the eXo Platform archive, kept in its own stage so
# build-only tools (curl, unzip) never ship in the runtime image
FROM ${BASE_IMAGE} AS downloader

# Build Arguments and environment variables
ARG EXO_VERSION=7.3.0-20260922
# this allow to specify an eXo Platform download url
ARG DOWNLOAD_URL
# this allow to specifiy a user to download a protected binary
ARG DOWNLOAD_USER
# Default base directory on the plf archive
ARG ARCHIVE_BASE_DIR=platform-${EXO_VERSION}
# Optional: expected sha256 of the downloaded archive, overriding the
# ${DOWNLOAD_URL}.sha256 sidecar published by downloads.exoplatform.org
# (auto-fetched and verified by default; a warning is printed only if
# neither is available, e.g. a custom mirror with no published checksum).
ARG EXO_ZIP_SHA256
# extra options passed to every apt-get install (e.g. proxy config: -o Acquire::http::Proxy=...)
ARG _APT_OPTIONS

RUN apt-get -qq update && \
  apt-get -qq -y install --no-install-recommends ${_APT_OPTIONS} \
    curl \
    unzip \
    ca-certificates && \
  apt-get -qq -y clean && \
  rm -rf /var/lib/apt/lists/*

# Download eXo Platform.
# Credentials for a protected DOWNLOAD_URL can be supplied two ways:
#   - DOWNLOAD_USER (username only) + an interactive password prompt, as before
#   - a BuildKit secret "download_password" for non-interactive/CI builds:
#       docker build --secret id=download_password,src=./password.txt \
#         --build-arg DOWNLOAD_URL=... --build-arg DOWNLOAD_USER=... .
RUN --mount=type=secret,id=download_password,required=false set -e; \
  if [ -n "${DOWNLOAD_USER}" ]; then \
    if [ -s /run/secrets/download_password ]; then \
      PARAMS="-u ${DOWNLOAD_USER}:$(cat /run/secrets/download_password)"; \
    else \
      PARAMS="-u ${DOWNLOAD_USER}"; \
    fi; \
  fi && \
  if [ ! -n "${DOWNLOAD_URL}" ]; then \
  echo "Building an image with eXo Platform version : ${EXO_VERSION}"; \
  EXO_VERSION_SHORT=$(echo ${EXO_VERSION} | awk -F "\." '{ print $1"."$2}'); \
  DOWNLOAD_URL="https://downloads.exoplatform.org/public/releases/platform/${EXO_VERSION_SHORT}/${EXO_VERSION}/platform-${EXO_VERSION}.zip"; \
  fi && \
  curl ${PARAMS} -fsSL -o /tmp/eXo-Platform.zip ${DOWNLOAD_URL} && \
  if [ -z "${EXO_ZIP_SHA256}" ]; then \
    EXO_ZIP_SHA256=$(curl -fsSL "${DOWNLOAD_URL}.sha256" 2>/dev/null | awk '{print $1}'); \
  fi && \
  if [ -n "${EXO_ZIP_SHA256}" ]; then \
    echo "${EXO_ZIP_SHA256} /tmp/eXo-Platform.zip" | sha256sum -c - \
    || { echo "ERROR: the downloaded eXo Platform archive does not match its expected sha256 checksum !!"; exit 1; }; \
  else \
    echo "WARNING: no sha256 checksum available (none provided via EXO_ZIP_SHA256 and none published at ${DOWNLOAD_URL}.sha256), skipping integrity verification"; \
  fi && \
  unzip -q /tmp/eXo-Platform.zip -d /tmp/exo-extracted && \
  mv /tmp/exo-extracted/${ARCHIVE_BASE_DIR} /tmp/exo-app && \
  rm -rf /tmp/eXo-Platform.zip /tmp/exo-extracted

# Runtime image
FROM ${BASE_IMAGE}

ARG YQ_VERSION=v4.53.6
ARG EXO_VERSION=7.3.0-20260922
# allow to override the list of addons to package by default
ARG ADDONS="exo-jdbc-driver-mysql:2.3.0 exo-jdbc-driver-postgresql:2.5.4"
# OCI image metadata, e.g.: --build-arg VCS_REF=$(git rev-parse --short HEAD) --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ARG VCS_REF
ARG BUILD_DATE
# extra options passed to every apt-get install (e.g. proxy config: -o Acquire::http::Proxy=...)
ARG _APT_OPTIONS

LABEL org.opencontainers.image.authors="eXo Platform <docker@exoplatform.com>" \
      org.opencontainers.image.title="eXo Platform Enterprise" \
      org.opencontainers.image.description="Docker image for eXo Platform Enterprise Edition" \
      org.opencontainers.image.vendor="eXo Platform" \
      org.opencontainers.image.source="https://github.com/exo-docker/exo-enterprise" \
      org.opencontainers.image.version="${EXO_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

ENV EXO_APP_DIR=/opt/exo \
    EXO_CONF_DIR=/etc/exo \
    EXO_CODEC_DIR=/etc/exo/codec \
    EXO_DATA_DIR=/srv/exo \
    EXO_SHARED_DATA_DIR=/srv/exo/shared \
    EXO_LOG_DIR=/var/log/exo \
    EXO_TMP_DIR=/tmp/exo-tmp \
    EXO_USER=exo \
    EXO_GROUP=exo \
    DEBIAN_FRONTEND=noninteractive

# add our user and group first to make sure their IDs get assigned consistently
RUN useradd --create-home -u 999 --user-group --shell /bin/bash --no-log-init ${EXO_USER}

# Install the needed packages
RUN apt-get -qq update && \
  apt-get -qq -y install --no-install-recommends ${_APT_OPTIONS} debconf-utils && \
  echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections && \
  echo "ttf-mscorefonts-installer msttcorefonts/present-mscorefonts-eula note" | debconf-set-selections && \
  apt-get -qq -y install --no-install-recommends ${_APT_OPTIONS} \
    xmlstarlet \
    jq \
    curl \
    ca-certificates \
    ttf-mscorefonts-installer \
    fontconfig && \
  apt-get -qq -y autoremove && \
  apt-get -qq -y clean && \
  rm -rf /var/lib/apt/lists/*

# Download yq with architecture detection and checksum verification
RUN YQ_ARCH=$(dpkg --print-architecture) && \
    if [ "$YQ_ARCH" = "amd64" ]; then \
        YQ_SHA256="c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385"; \
    elif [ "$YQ_ARCH" = "arm64" ]; then \
        YQ_SHA256="88a1016bc1d657375a35864e4f44b6f333df8ff97b559f51bba0adcb2169df09"; \
    else \
        echo "Unsupported architecture: $YQ_ARCH"; exit 1; \
    fi && \
    curl -fsSL -o /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" && \
    echo "${YQ_SHA256} /usr/bin/yq" | sha256sum -c - \
    || { \
    echo "ERROR: the [/usr/bin/yq] binary downloaded from a github release was modified while it should not !!"; \
    exit 1; \
    } && \
    chmod a+x /usr/bin/yq

# Drop pebble as we use tini
RUN rm -f /usr/bin/pebble \
    && rm -rf /var/lib/pebble \
    && rm -rf /etc/pebble

# Create needed directories
RUN mkdir -p ${EXO_DATA_DIR}         && chown ${EXO_USER}:${EXO_GROUP} ${EXO_DATA_DIR} && \
  mkdir -p ${EXO_SHARED_DATA_DIR}  && chown ${EXO_USER}:${EXO_GROUP} ${EXO_SHARED_DATA_DIR} && \
  mkdir -p ${EXO_TMP_DIR}          && chown ${EXO_USER}:${EXO_GROUP} ${EXO_TMP_DIR}  && \
  mkdir -p ${EXO_LOG_DIR}          && chown ${EXO_USER}:${EXO_GROUP} ${EXO_LOG_DIR}

# Install eXo Platform (built in the "downloader" stage above)
COPY --from=downloader --chown=${EXO_USER}:${EXO_GROUP} /tmp/exo-app ${EXO_APP_DIR}
RUN ln -s ${EXO_APP_DIR}/gatein/conf ${EXO_CONF_DIR} && \
  mkdir -p ${EXO_CODEC_DIR} && chown ${EXO_USER}:${EXO_GROUP} ${EXO_CODEC_DIR} && \
  rm -rf ${EXO_APP_DIR}/logs && ln -s ${EXO_LOG_DIR} ${EXO_APP_DIR}/logs

# Install Docker customization file
COPY --chown=${EXO_USER}:${EXO_GROUP} bin/setenv-docker-customize.sh ${EXO_APP_DIR}/bin/setenv-docker-customize.sh
RUN chmod 755 ${EXO_APP_DIR}/bin/setenv-docker-customize.sh && \
  sed -i '/# Load custom settings/i \
  \# Load custom settings for docker environment\n\
  [ -r "$CATALINA_BASE/bin/setenv-docker-customize.sh" ] \
  && . "$CATALINA_BASE/bin/setenv-docker-customize.sh" \
  || echo "No Docker eXo Platform customization file : $CATALINA_BASE/bin/setenv-docker-customize.sh"\n\
  ' ${EXO_APP_DIR}/bin/setenv.sh && \
  grep 'setenv-docker-customize.sh' ${EXO_APP_DIR}/bin/setenv.sh

USER ${EXO_USER}

RUN for a in ${ADDONS}; do \
      echo "Installing addon $a"; \
      /opt/exo/addon install $a || { echo "ERROR: failed to install addon $a"; exit 1; }; \
    done

WORKDIR ${EXO_LOG_DIR}
ENTRYPOINT ["/usr/local/bin/tini", "--"]
# Health Check
HEALTHCHECK --interval=30s --timeout=5s --start-period=300s --retries=3 \
  CMD curl --fail http://localhost:8080/ || exit 1
CMD [ "/opt/exo/start_eXo.sh" ]
