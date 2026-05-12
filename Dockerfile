# Dockerizing base image for eXo Platform hosting offer with:
#
# - eXo Platform Enterprise Edition
#
# Build:    docker build -t exoplatform/exo-enterprise .
#           docker build --build-arg EXO_VERSION=7.2.0 -t exoplatform/exo-enterprise .
#
# Run:      docker run -d --name=exo -p 80:8080 exoplatform/exo-enterprise
#           docker run -d --name=exo -p 80:8080 \
#             -e EXO_DB_TYPE=pgsql \
#             -e EXO_DB_HOST=db \
#             -e EXO_DB_PASSWORD=secret \
#             exoplatform/exo-enterprise

# ---------------------------------------------------------------------------
# Stage 1: dependency downloader (maximises layer cache reuse)
# ---------------------------------------------------------------------------
FROM exoplatform/jdk:openjdk-21-ubuntu-2604 AS downloader

ARG EXO_VERSION=7.2.0-M28
ARG DOWNLOAD_URL
ARG DOWNLOAD_USER
ARG ARCHIVE_BASE_DIR=platform-${EXO_VERSION}
ARG YQ_VERSION=v4.53.2

RUN apt-get -qq update && \
    apt-get -qq -y install --no-install-recommends curl unzip ca-certificates && \
    apt-get -qq -y clean && \
    rm -rf /var/lib/apt/lists/*

# Download yq with architecture detection and checksum verification
RUN set -e; \
    YQ_ARCH=$(dpkg --print-architecture); \
    case "$YQ_ARCH" in \
      amd64) YQ_SHA256="d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b" ;; \
      arm64) YQ_SHA256="03061b2a50c7a498de2bbb92d7cb078ce433011f085a4994117c2726be4106ea" ;; \
      *) echo "Unsupported architecture: $YQ_ARCH"; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}"; \
    echo "${YQ_SHA256} /usr/bin/yq" | sha256sum -c - || { \
      echo "ERROR: yq binary checksum mismatch – aborting!"; exit 1; \
    }; \
    chmod 0755 /usr/bin/yq

# Download and unpack eXo Platform archive
RUN set -e; \
    if [ -n "${DOWNLOAD_USER}" ]; then PARAMS="-u ${DOWNLOAD_USER}"; fi; \
    if [ -z "${DOWNLOAD_URL}" ]; then \
      EXO_VERSION_SHORT=$(echo "${EXO_VERSION}" | awk -F "." '{ print $1"."$2}'); \
      DOWNLOAD_URL="https://downloads.exoplatform.org/public/releases/platform/${EXO_VERSION_SHORT}/${EXO_VERSION}/platform-${EXO_VERSION}.zip"; \
    fi; \
    echo "Downloading eXo Platform ${EXO_VERSION} ..."; \
    curl ${PARAMS:-} -fsSL -o /tmp/eXo-Platform.zip "${DOWNLOAD_URL}"; \
    unzip -q /tmp/eXo-Platform.zip -d /opt/; \
    mv /opt/${ARCHIVE_BASE_DIR} /opt/exo; \
    rm -f /tmp/eXo-Platform.zip

# ---------------------------------------------------------------------------
# Stage 2: final runtime image
# ---------------------------------------------------------------------------
FROM exoplatform/jdk:openjdk-21-ubuntu-2604

LABEL org.opencontainers.image.authors="eXo Platform <docker@exoplatform.com>" \
      org.opencontainers.image.title="eXo Platform Enterprise" \
      org.opencontainers.image.description="Docker image for eXo Platform Enterprise Edition" \
      org.opencontainers.image.vendor="eXo Platform" \
      org.opencontainers.image.source="https://github.com/exo-docker/exo-enterprise"

ARG EXO_VERSION=7.2.0-M28
ARG ADDONS="exo-jdbc-driver-mysql:2.1.0 exo-jdbc-driver-postgresql:2.5.2"

LABEL org.opencontainers.image.version="${EXO_VERSION}"

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

# Create dedicated user first (consistent UID/GID 999)
RUN useradd --create-home -u 999 --user-group --shell /bin/bash ${EXO_USER}

# Install runtime packages in a single layer
RUN apt-get -qq update && \
    apt-get -qq -y upgrade && \
    apt-get -qq -y install --no-install-recommends \
      debconf-utils \
      xmlstarlet \
      jq \
      curl \
      unzip \
      ca-certificates \
      fontconfig \
      openssl && \
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections && \
    echo "ttf-mscorefonts-installer msttcorefonts/present-mscorefonts-eula note" | debconf-set-selections && \
    apt-get -qq -y install --no-install-recommends ttf-mscorefonts-installer && \
    apt-get -qq -y autoremove && \
    apt-get -qq -y clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy pre-built artefacts from downloader stage
COPY --from=downloader /usr/bin/yq /usr/bin/yq
COPY --from=downloader /opt/exo    ${EXO_APP_DIR}

# Drop pebble (replaced by tini)
RUN rm -f /usr/bin/pebble && \
    rm -rf /var/lib/pebble /etc/pebble

# Create runtime directories with correct ownership
RUN mkdir -p \
      ${EXO_DATA_DIR} \
      ${EXO_SHARED_DATA_DIR} \
      ${EXO_TMP_DIR} \
      ${EXO_LOG_DIR} \
      ${EXO_CODEC_DIR} && \
    chown -R ${EXO_USER}:${EXO_GROUP} \
      ${EXO_DATA_DIR} \
      ${EXO_SHARED_DATA_DIR} \
      ${EXO_TMP_DIR} \
      ${EXO_LOG_DIR} \
      ${EXO_CODEC_DIR} \
      ${EXO_APP_DIR}

# Wire up directories and configuration symlinks
RUN ln -sf ${EXO_CONF_DIR} ${EXO_APP_DIR}/gatein/conf && \
    rm -rf   ${EXO_APP_DIR}/logs && \
    ln -s    ${EXO_LOG_DIR} ${EXO_APP_DIR}/logs

# Install Docker customisation script (owned by exo, not world-writable)
COPY --chown=${EXO_USER}:${EXO_GROUP} bin/setenv-docker-customize.sh \
     ${EXO_APP_DIR}/bin/setenv-docker-customize.sh
RUN chmod 750 ${EXO_APP_DIR}/bin/setenv-docker-customize.sh && \
    sed -i '/# Load custom settings/i \
  # Load custom settings for docker environment\n\
  [ -r "$CATALINA_BASE/bin/setenv-docker-customize.sh" ] \\\n\
  \&\& . "$CATALINA_BASE/bin/setenv-docker-customize.sh" \\\n\
  || echo "No Docker eXo Platform customization file : $CATALINA_BASE/bin/setenv-docker-customize.sh"\n\
  ' ${EXO_APP_DIR}/bin/setenv.sh && \
    grep -q 'setenv-docker-customize.sh' ${EXO_APP_DIR}/bin/setenv.sh

# Install bundled add-ons as the exo user
USER ${EXO_USER}
RUN for a in ${ADDONS}; do \
      echo "INFO: Installing addon $a ..."; \
      /opt/exo/addon install "$a" || { echo "ERROR: Failed to install addon $a"; exit 1; }; \
    done

WORKDIR ${EXO_LOG_DIR}

ENTRYPOINT ["/usr/local/bin/tini", "--"]

# Health check – wait up to 3 min for the portal to respond
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
  CMD curl -fs http://localhost:8080/portal/login || exit 1

CMD ["/opt/exo/start_eXo.sh"]
