# Dockerizing base image for eXo Platform hosting offer with:
#
# - eXo Platform

# Build:    docker build -t exoplatform/exo-enterprise .
#
# Run:      docker run -ti --rm --name=exo -p 80:8080 exoplatform/exo-enterprise
#           docker run -d --name=exo -p 80:8080 exoplatform/exo-enterprise

FROM  exoplatform/jdk:openjdk-21-ubuntu-2404

LABEL org.opencontainers.image.authors="eXo Platform <docker@exoplatform.com>" \
      org.opencontainers.image.title="eXo Platform Enterprise" \
      org.opencontainers.image.description="Docker image for eXo Platform Enterprise Edition" \
      org.opencontainers.image.vendor="eXo Platform"

ARG YQ_VERSION=v4.52.4
ARG YQ_SHA256=0c4d965ea944b64b8fddaf7f27779ee3034e5693263786506ccd1c120f184e8c

# Build Arguments and environment variables
ARG EXO_VERSION=7.2.0-20260225

# this allow to specify an eXo Platform download url
ARG DOWNLOAD_URL
# this allow to specifiy a user to download a protected binary
ARG DOWNLOAD_USER
# allow to override the list of addons to package by default
ARG ADDONS="exo-jdbc-driver-mysql:2.1.0 exo-jdbc-driver-postgresql:2.5.2"
# Default base directory on the plf archive
ARG ARCHIVE_BASE_DIR=platform-${EXO_VERSION}

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
RUN useradd --create-home -u 999 --user-group --shell /bin/bash ${EXO_USER}

# Install the needed packages
RUN apt-get -qq update && \
  apt-get -qq -y upgrade ${_APT_OPTIONS} && \
  apt-get -qq -y install --no-install-recommends ${_APT_OPTIONS} debconf-utils && \
  echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections && \
  echo "ttf-mscorefonts-installer msttcorefonts/present-mscorefonts-eula note" | debconf-set-selections && \
  apt-get -qq -y install --no-install-recommends ${_APT_OPTIONS} \
    xmlstarlet \
    jq \
    curl \
    unzip \
    ca-certificates \
    ttf-mscorefonts-installer \
    fontconfig && \
  apt-get -qq -y autoremove && \
  apt-get -qq -y clean && \
  rm -rf /var/lib/apt/lists/* && \
  # Check if the released binary was modified and make the build fail if it is the case
  curl -fsSL -o /usr/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" && \
  echo "${YQ_SHA256} /usr/bin/yq" | sha256sum -c - \
  || { \
  echo "ERROR: the [/usr/bin/yq] binary downloaded from a github release was modified while is should not !!"; \
  return 1; \
  } && chmod a+x /usr/bin/yq

# Create needed directories
RUN mkdir -p ${EXO_DATA_DIR}         && chown ${EXO_USER}:${EXO_GROUP} ${EXO_DATA_DIR} && \
  mkdir -p ${EXO_SHARED_DATA_DIR}  && chown ${EXO_USER}:${EXO_GROUP} ${EXO_SHARED_DATA_DIR} && \
  mkdir -p ${EXO_TMP_DIR}          && chown ${EXO_USER}:${EXO_GROUP} ${EXO_TMP_DIR}  && \
  mkdir -p ${EXO_LOG_DIR}          && chown ${EXO_USER}:${EXO_GROUP} ${EXO_LOG_DIR}

# Install eXo Platform
RUN set -e; \
  if [ -n "${DOWNLOAD_USER}" ]; then PARAMS="-u ${DOWNLOAD_USER}"; fi && \
  if [ ! -n "${DOWNLOAD_URL}" ]; then \
  echo "Building an image with eXo Platform version : ${EXO_VERSION}"; \
  EXO_VERSION_SHORT=$(echo ${EXO_VERSION} | awk -F "\." '{ print $1"."$2}'); \
  DOWNLOAD_URL="https://downloads.exoplatform.org/public/releases/platform/${EXO_VERSION_SHORT}/${EXO_VERSION}/platform-${EXO_VERSION}.zip"; \
  fi && \
  curl ${PARAMS} -sS -L -o /tmp/eXo-Platform.zip ${DOWNLOAD_URL} && \
  unzip -q /tmp/eXo-Platform.zip -d /tmp/ && \
  rm -f /tmp/eXo-Platform.zip && \
  mv /tmp/${ARCHIVE_BASE_DIR} ${EXO_APP_DIR} && \
  chown -R ${EXO_USER}:${EXO_GROUP} ${EXO_APP_DIR} && \
  ln -s ${EXO_APP_DIR}/gatein/conf ${EXO_CONF_DIR} && \
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

RUN for a in ${ADDONS}; do echo "Installing addon $a"; /opt/exo/addon install $a; done

WORKDIR ${EXO_LOG_DIR}
ENTRYPOINT ["/usr/local/bin/tini", "--"]
# Health Check
HEALTHCHECK CMD curl --fail http://localhost:8080/ || exit 1
CMD [ "/opt/exo/start_eXo.sh" ]