#!/bin/bash -eu
# -----------------------------------------------------------------------------
#
# Settings customization – Docker environment
#
# Refer to eXo Platform Administrators Guide for more details.
# https://docs.exoplatform.com
#
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Helper: replace a pattern inside a file (avoids in-place sed portability issues)
# ---------------------------------------------------------------------------
replace_in_file() {
  local _file="$1" _search="$2" _replace="$3"
  local _tmp
  _tmp=$(mktemp /tmp/replace.XXXXXXXXXX) || { echo "ERROR: Failed to create temp file"; exit 1; }
  sed "s|${_search}|${_replace}|g" "${_file}" > "${_tmp}"
  mv "${_tmp}" "${_file}"
}

# ---------------------------------------------------------------------------
# Helper: append a line to the eXo docker.properties file
# ---------------------------------------------------------------------------
add_in_exo_configuration() {
  local EXO_CONFIG_FILE="/etc/exo/docker.properties"
  if [ ! -f "${EXO_CONFIG_FILE}" ]; then
    echo "INFO: Creating eXo Docker configuration file [${EXO_CONFIG_FILE}]"
    touch "${EXO_CONFIG_FILE}" || { echo "ERROR: Cannot create ${EXO_CONFIG_FILE}, aborting!"; exit 1; }
  fi
  # Guarantee the new line starts on its own line
  [ -s "${EXO_CONFIG_FILE}" ] && tail -c1 "${EXO_CONFIG_FILE}" | read -r _ || echo >> "${EXO_CONFIG_FILE}"
  echo "$1" >> "${EXO_CONFIG_FILE}"
}

# ---------------------------------------------------------------------------
# Helper: append a line to the Chat configuration file
# ---------------------------------------------------------------------------
add_in_chat_configuration() {
  local _CONFIG_FILE="/etc/exo/chat.properties"
  if [ ! -f "${_CONFIG_FILE}" ]; then
    echo "INFO: Creating Chat configuration file [${_CONFIG_FILE}]"
    touch "${_CONFIG_FILE}" || { echo "ERROR: Cannot create ${_CONFIG_FILE}, aborting!"; exit 1; }
  fi
  echo "$1" >> "${_CONFIG_FILE}"
}

# ---------------------------------------------------------------------------
# Guard: refuse to start if exo.properties exists but is empty
# ---------------------------------------------------------------------------
check_exo_properties() {
  local _f="/etc/exo/exo.properties"
  if [ -f "${_f}" ] && ! grep -q '[^[:space:]]' "${_f}"; then
    echo "ERROR: ${_f} exists but is empty – refusing to start to avoid misconfiguration."
    kill 1
  fi
}

# ---------------------------------------------------------------------------
# Secret injection: EXO_SEC_*_FILE  →  EXO_*
# Priority: direct ENV wins unless EXO_SEC_*_FILE_FORCE=true
# ---------------------------------------------------------------------------
for _env_var in $(env | grep -E '^EXO_SEC_.*_FILE=' | cut -d= -f1); do
  _file_path="${!_env_var}"
  _target_var="${_env_var/_SEC_/_}"
  _target_var="${_target_var%_FILE}"
  _direct_exists=$(env | grep -E "^${_target_var}=" || true)
  _force_var="${_env_var}_FORCE"
  _force_override="${!_force_var:-false}"

  if [ ! -f "${_file_path}" ]; then
    echo "WARNING: Secret file ${_file_path} declared in ${_env_var} does not exist!"
    continue
  fi

  if [ -n "${_direct_exists}" ] && [ "${_force_override}" != "true" ]; then
    echo "INFO: ${_target_var} already set via environment – skipping ${_file_path}"
    echo "      (set ${_force_var}=true to override)"
  else
    [ -n "${_direct_exists}" ] && echo "WARNING: Overriding ${_target_var} from ${_file_path} (forced)"
    export "${_target_var}"="$(< "${_file_path}")"
    echo "INFO: Loaded secret from ${_file_path} into ${_target_var}"
  fi
done

# ---------------------------------------------------------------------------
# Default values for all configuration variables
# ---------------------------------------------------------------------------
set +u  # allow unbound variables while applying defaults

[ -z "${EXO_FILE_UMASK}" ]       && UMASK="0022"            || UMASK="${EXO_FILE_UMASK}"
umask "${UMASK}"

[ -z "${EXO_PROXY_VHOST}" ]      && EXO_PROXY_VHOST="localhost"
[ -z "${EXO_PROXY_SSL}" ]        && EXO_PROXY_SSL="true"
[ -z "${EXO_PROXY_PORT}" ] && {
  case "${EXO_PROXY_SSL}" in
    true)  EXO_PROXY_PORT="443" ;;
    false) EXO_PROXY_PORT="80"  ;;
    *)     EXO_PROXY_PORT="80"  ;;
  esac
}

[ -z "${EXO_DATA_DIR}" ]                 && EXO_DATA_DIR="/srv/exo"
[ -z "${EXO_JCR_STORAGE_DIR}" ]          && EXO_JCR_STORAGE_DIR="${EXO_DATA_DIR}/jcr/values"
[ -z "${EXO_FILE_STORAGE_DIR}" ]         && EXO_FILE_STORAGE_DIR="${EXO_DATA_DIR}/files"
[ -z "${EXO_FILE_STORAGE_RETENTION}" ]   && EXO_FILE_STORAGE_RETENTION="30"

# Database
[ -z "${EXO_DB_TIMEOUT}" ]               && EXO_DB_TIMEOUT="60"
[ -z "${EXO_DB_TYPE}" ]                  && EXO_DB_TYPE="mysql"
case "${EXO_DB_TYPE}" in
  hsqldb)
    cat <<'WARN'
################################################################################
# WARNING: HSQLDB is NOT recommended for production use.
################################################################################
WARN
    sleep 2
    ;;
  mysql)
    [ -z "${EXO_DB_NAME}" ]          && EXO_DB_NAME="exo"
    [ -z "${EXO_DB_USER}" ]          && EXO_DB_USER="exo"
    [ -z "${EXO_DB_HOST}" ]          && EXO_DB_HOST="db"
    [ -z "${EXO_DB_PORT}" ]          && EXO_DB_PORT="3306"
    [ -z "${EXO_DB_MYSQL_USE_SSL}" ] && EXO_DB_MYSQL_USE_SSL="false"
    [ -z "${EXO_DB_PASSWORD:-}" ]    && { echo "ERROR: EXO_DB_PASSWORD is required for MySQL"; exit 1; }
    ;;
  pgsql|postgres|postgresql)
    [ -z "${EXO_DB_NAME}" ]          && EXO_DB_NAME="exo"
    [ -z "${EXO_DB_USER}" ]          && EXO_DB_USER="exo"
    [ -z "${EXO_DB_HOST}" ]          && EXO_DB_HOST="db"
    [ -z "${EXO_DB_PORT}" ]          && EXO_DB_PORT="5432"
    [ -z "${EXO_DB_PASSWORD:-}" ]    && { echo "ERROR: EXO_DB_PASSWORD is required for PostgreSQL"; exit 1; }
    ;;
  *)
    echo "ERROR: Unsupported EXO_DB_TYPE='${EXO_DB_TYPE}'. Supported values: hsqldb | mysql | pgsql"
    exit 1
    ;;
esac

[ -z "${EXO_DB_POOL_IDM_INIT_SIZE}" ]  && EXO_DB_POOL_IDM_INIT_SIZE="5"
[ -z "${EXO_DB_POOL_IDM_MAX_SIZE}" ]   && EXO_DB_POOL_IDM_MAX_SIZE="20"
[ -z "${EXO_DB_POOL_JCR_INIT_SIZE}" ]  && EXO_DB_POOL_JCR_INIT_SIZE="5"
[ -z "${EXO_DB_POOL_JCR_MAX_SIZE}" ]   && EXO_DB_POOL_JCR_MAX_SIZE="20"
[ -z "${EXO_DB_POOL_JPA_INIT_SIZE}" ]  && EXO_DB_POOL_JPA_INIT_SIZE="5"
[ -z "${EXO_DB_POOL_JPA_MAX_SIZE}" ]   && EXO_DB_POOL_JPA_MAX_SIZE="20"

[ -z "${EXO_UPLOAD_MAX_FILE_SIZE}" ]   && EXO_UPLOAD_MAX_FILE_SIZE="200"

[ -z "${EXO_HTTP_THREAD_MIN}" ]        && EXO_HTTP_THREAD_MIN="10"
[ -z "${EXO_HTTP_THREAD_MAX}" ]        && EXO_HTTP_THREAD_MAX="200"
[ -z "${EXO_HTTP_HEADER_MAX}" ]        && EXO_HTTP_HEADER_MAX="8192"

[ -z "${EXO_MAIL_FROM}" ]              && EXO_MAIL_FROM="noreply@exoplatform.com"
[ -z "${EXO_MAIL_SMTP_HOST}" ]         && EXO_MAIL_SMTP_HOST="localhost"
[ -z "${EXO_MAIL_SMTP_PORT}" ]         && EXO_MAIL_SMTP_PORT="25"
[ -z "${EXO_MAIL_SMTP_STARTTLS}" ]     && EXO_MAIL_SMTP_STARTTLS="false"
[ -z "${EXO_MAIL_SMTP_USERNAME}" ]     && EXO_MAIL_SMTP_USERNAME="-"
[ -z "${EXO_MAIL_SMTP_PASSWORD}" ]     && EXO_MAIL_SMTP_PASSWORD="-"

[ -z "${EXO_JVM_LOG_GC_ENABLED}" ]     && EXO_JVM_LOG_GC_ENABLED="false"

[ -z "${EXO_JMX_ENABLED}" ]            && EXO_JMX_ENABLED="true"
[ -z "${EXO_JMX_RMI_REGISTRY_PORT}" ]  && EXO_JMX_RMI_REGISTRY_PORT="10001"
[ -z "${EXO_JMX_RMI_SERVER_PORT}" ]    && EXO_JMX_RMI_SERVER_PORT="10002"
[ -z "${EXO_JMX_RMI_SERVER_HOSTNAME}" ] && EXO_JMX_RMI_SERVER_HOSTNAME="localhost"
[ -z "${EXO_JMX_USERNAME}" ]           && EXO_JMX_USERNAME="-"
[ -z "${EXO_JMX_PASSWORD}" ]           && EXO_JMX_PASSWORD="-"

[ -z "${EXO_ACCESS_LOG_ENABLED}" ]     && EXO_ACCESS_LOG_ENABLED="false"

[ -z "${EXO_MONGO_TIMEOUT}" ]          && EXO_MONGO_TIMEOUT="60"
[ -z "${EXO_MONGO_HOST}" ]             && EXO_MONGO_HOST="mongo"
[ -z "${EXO_MONGO_PORT}" ]             && EXO_MONGO_PORT="27017"
[ -z "${EXO_MONGO_USERNAME}" ]         && EXO_MONGO_USERNAME="-"
[ -z "${EXO_MONGO_PASSWORD}" ]         && EXO_MONGO_PASSWORD="-"
[ -z "${EXO_MONGO_DB_NAME}" ]          && EXO_MONGO_DB_NAME="chat"

[ -z "${EXO_CHAT_SERVER_STANDALONE}" ] && EXO_CHAT_SERVER_STANDALONE="false"
[ -z "${EXO_CHAT_SERVER_URL}" ]        && EXO_CHAT_SERVER_URL="http://localhost:8080"
[ -z "${EXO_CHAT_SERVICE_URL}" ]       && EXO_CHAT_SERVICE_URL=""
[ -z "${EXO_CHAT_SERVER_PASSPHRASE}" ] && EXO_CHAT_SERVER_PASSPHRASE="something2change"

[ -z "${EXO_ES_TIMEOUT}" ]             && EXO_ES_TIMEOUT="60"
[ -z "${EXO_ES_SCHEME}" ]              && EXO_ES_SCHEME="http"
[ -z "${EXO_ES_HOST}" ]                && EXO_ES_HOST="localhost"
[ -z "${EXO_ES_PORT}" ]                && EXO_ES_PORT="9200"
EXO_ES_URL="${EXO_ES_SCHEME}://${EXO_ES_HOST}:${EXO_ES_PORT}"
[ -z "${EXO_ES_USERNAME}" ]            && EXO_ES_USERNAME="-"
[ -z "${EXO_ES_PASSWORD}" ]            && EXO_ES_PASSWORD="-"
[ -z "${EXO_ES_INDEX_REPLICA_NB}" ]    && EXO_ES_INDEX_REPLICA_NB="1"
[ -z "${EXO_ES_INDEX_SHARD_NB}" ]      && EXO_ES_INDEX_SHARD_NB="5"

[ -z "${EXO_WAIT_FOR_MATRIX}" ]        && EXO_WAIT_FOR_MATRIX="false"
[ -z "${EXO_MATRIX_HOST}" ]            && EXO_MATRIX_HOST="matrix"
[ -z "${EXO_MATRIX_PORT}" ]            && EXO_MATRIX_PORT="8008"
[ -z "${EXO_MATRIX_TIMEOUT}" ]         && EXO_MATRIX_TIMEOUT="30"

[ -z "${EXO_LDAP_POOL_TIMEOUT}" ]      && EXO_LDAP_POOL_TIMEOUT="60000"
[ -z "${EXO_LDAP_POOL_MAX_SIZE}" ]     && EXO_LDAP_POOL_MAX_SIZE="100"

[ -z "${EXO_REGISTRATION}" ]           && EXO_REGISTRATION="true"
[ -z "${EXO_PROFILES}" ]               && EXO_PROFILES="all"

[ -z "${EXO_REWARDS_WALLET_ADMIN_KEY}" ]                   && EXO_REWARDS_WALLET_ADMIN_KEY="changeThisKey"
[ -z "${EXO_REWARDS_WALLET_NETWORK_ID}" ]                  && EXO_REWARDS_WALLET_NETWORK_ID="1"
[ -z "${EXO_REWARDS_WALLET_NETWORK_ENDPOINT_HTTP}" ]       && EXO_REWARDS_WALLET_NETWORK_ENDPOINT_HTTP="https://mainnet.infura.io/v3/a1ac85aea9ce4be88e9e87dad7c01d40"
[ -z "${EXO_REWARDS_WALLET_NETWORK_ENDPOINT_WEBSOCKET}" ]  && EXO_REWARDS_WALLET_NETWORK_ENDPOINT_WEBSOCKET="wss://mainnet.infura.io/ws/v3/a1ac85aea9ce4be88e9e87dad7c01d40"
[ -z "${EXO_REWARDS_WALLET_TOKEN_ADDRESS}" ]               && EXO_REWARDS_WALLET_TOKEN_ADDRESS="0xc76987d43b77c45d51653b6eb110b9174acce8fb"

[ -z "${EXO_AGENDA_GOOGLE_CONNECTOR_ENABLED}" ]            && EXO_AGENDA_GOOGLE_CONNECTOR_ENABLED="true"
[ -z "${EXO_AGENDA_OFFICE_CONNECTOR_ENABLED}" ]            && EXO_AGENDA_OFFICE_CONNECTOR_ENABLED="true"
[ -z "${EXO_AGENDA_GOOGLE_CONNECTOR_CLIENT_API_KEY}" ]     && EXO_AGENDA_GOOGLE_CONNECTOR_CLIENT_API_KEY=""
[ -z "${EXO_AGENDA_OFFICE_CONNECTOR_CLIENT_API_KEY}" ]     && EXO_AGENDA_OFFICE_CONNECTOR_CLIENT_API_KEY=""

[ -z "${EXO_ADDONS_CONFLICT_MODE}" ]   && EXO_ADDONS_CONFLICT_MODE=""
[ -z "${EXO_ADDONS_NOCOMPAT_MODE}" ]   && EXO_ADDONS_NOCOMPAT_MODE="false"
[ -z "${EXO_ADDONS_INSTALL_TIMEOUT}" ] && EXO_ADDONS_INSTALL_TIMEOUT=120

[ -z "${EXO_JCR_FS_STORAGE_ENABLED}" ] && EXO_JCR_FS_STORAGE_ENABLED=""
[ -z "${EXO_FILE_STORAGE_TYPE}" ]       && EXO_FILE_STORAGE_TYPE=""
[ -z "${EXO_CLUSTER_NODE_NAME}" ]       && EXO_CLUSTER_NODE_NAME=""

[ -z "${EXO_TOKEN_REMEMBERME_EXPIRATION_VALUE}" ] && EXO_TOKEN_REMEMBERME_EXPIRATION_VALUE="7"
[ -z "${EXO_TOKEN_REMEMBERME_EXPIRATION_UNIT}" ]  && EXO_TOKEN_REMEMBERME_EXPIRATION_UNIT="DAY"
[ -z "${EXO_GZIP_ENABLED}" ]           && EXO_GZIP_ENABLED="true"
[ -z "${EXO_SESSION_TIMEOUT}" ]        && EXO_SESSION_TIMEOUT=30
[ -z "${EXO_CACERTS}" ]                && EXO_CACERTS=""
[ -z "${EXO_CACERTS_STOREPASS}" ]      && EXO_CACERTS_STOREPASS="changeit"

set -u  # re-enable unbound variable check

# ---------------------------------------------------------------------------
# One-time configuration (guarded by sentinel file)
# ---------------------------------------------------------------------------
if [ -f /opt/exo/_done.configuration ]; then
  echo "INFO: Configuration already applied – skipping."
else
  echo "INFO: Applying first-time configuration ..."

  # JCR storage
  add_in_exo_configuration "# JCR storage configuration"
  [ -n "${EXO_JCR_FS_STORAGE_ENABLED}" ] && \
    add_in_exo_configuration "exo.jcr.storage.enabled=${EXO_JCR_FS_STORAGE_ENABLED}"
  add_in_exo_configuration "exo.jcr.storage.data.dir=${EXO_JCR_STORAGE_DIR}"

  # File storage
  add_in_exo_configuration "# File storage configuration"
  [ -n "${EXO_FILE_STORAGE_TYPE}" ] && \
    add_in_exo_configuration "exo.files.binaries.storage.type=${EXO_FILE_STORAGE_TYPE}"
  add_in_exo_configuration "exo.files.storage.dir=${EXO_FILE_STORAGE_DIR}"
  add_in_exo_configuration "exo.commons.FileStorageCleanJob.retention-time=${EXO_FILE_STORAGE_RETENTION}"

  # Database configuration
  case "${EXO_DB_TYPE}" in
    hsqldb)
      cat /opt/exo/conf/server-hsqldb.xml > /opt/exo/conf/server.xml
      ;;
    mysql)
      cat /opt/exo/conf/server-mysql.xml > /opt/exo/conf/server.xml
      replace_in_file /opt/exo/conf/server.xml \
        "jdbc:mysql://localhost:3306/plf?autoReconnect=true" \
        "jdbc:mysql://${EXO_DB_HOST}:${EXO_DB_PORT}/${EXO_DB_NAME}?autoReconnect=true\&amp;useSSL=${EXO_DB_MYSQL_USE_SSL}\&amp;allowPublicKeyRetrieval=true"
      replace_in_file /opt/exo/conf/server.xml \
        'username="plf" password="plf"' \
        "username=\"${EXO_DB_USER}\" password=\"${EXO_DB_PASSWORD}\""
      ;;
    pgsql|postgres|postgresql)
      cat /opt/exo/conf/server-postgres.xml > /opt/exo/conf/server.xml
      replace_in_file /opt/exo/conf/server.xml \
        "jdbc:postgresql://localhost:5432/plf" \
        "jdbc:postgresql://${EXO_DB_HOST}:${EXO_DB_PORT}/${EXO_DB_NAME}"
      replace_in_file /opt/exo/conf/server.xml \
        'username="plf" password="plf"' \
        "username=\"${EXO_DB_USER}\" password=\"${EXO_DB_PASSWORD}\""
      ;;
  esac

  # Strip XML comments
  xmlstarlet ed -L -d "//comment()" /opt/exo/conf/server.xml || \
    { echo "ERROR: xmlstarlet failed removing XML comments"; exit 1; }

  # Connection pool tuning
  for _pool_name in exo-idm_portal exo-jcr_portal exo-jpa_portal; do
    case "${_pool_name}" in
      exo-idm_portal) _init=${EXO_DB_POOL_IDM_INIT_SIZE}; _max=${EXO_DB_POOL_IDM_MAX_SIZE} ;;
      exo-jcr_portal) _init=${EXO_DB_POOL_JCR_INIT_SIZE}; _max=${EXO_DB_POOL_JCR_MAX_SIZE} ;;
      exo-jpa_portal) _init=${EXO_DB_POOL_JPA_INIT_SIZE}; _max=${EXO_DB_POOL_JPA_MAX_SIZE} ;;
    esac
    xmlstarlet ed -L \
      -u "/Server/GlobalNamingResources/Resource[@name='${_pool_name}']/@initialSize" -v "${_init}" \
      -u "/Server/GlobalNamingResources/Resource[@name='${_pool_name}']/@minIdle"     -v "${_init}" \
      -u "/Server/GlobalNamingResources/Resource[@name='${_pool_name}']/@maxIdle"     -v "${_init}" \
      -u "/Server/GlobalNamingResources/Resource[@name='${_pool_name}']/@maxActive"   -v "${_max}"  \
      /opt/exo/conf/server.xml || \
      { echo "ERROR: xmlstarlet failed configuring pool ${_pool_name}"; exit 1; }
  done

  # Remove AJP connector
  xmlstarlet ed -L -d '//Connector[@protocol="AJP/1.3"]' /opt/exo/conf/server.xml || \
    { echo "ERROR: xmlstarlet failed removing AJP connector"; exit 1; }

  # Cluster jvmRoute
  if [ -n "${EXO_CLUSTER_NODE_NAME}" ]; then
    xmlstarlet ed -L \
      -d "/Server/Service/Engine/@jvmRoute" /opt/exo/conf/server.xml && \
    xmlstarlet ed -L \
      -s "/Server/Service/Engine" -t attr -n "jvmRoute" -v "${EXO_CLUSTER_NODE_NAME}" \
      /opt/exo/conf/server.xml || \
      { echo "ERROR: xmlstarlet failed setting jvmRoute"; exit 1; }
  fi

  # Force JSESSIONID into cookies
  xmlstarlet ed -L -d "/Context/@cookies" /opt/exo/conf/context.xml && \
  xmlstarlet ed -L -s "/Context" -t attr -n "cookies" -v "true" /opt/exo/conf/context.xml || \
    { echo "ERROR: xmlstarlet failed setting cookies mode"; exit 1; }

  # Proxy configuration
  xmlstarlet ed -L \
    -s "/Server/Service/Connector" -t attr -n "proxyName" -v "${EXO_PROXY_VHOST}" \
    /opt/exo/conf/server.xml || \
    { echo "ERROR: xmlstarlet failed adding proxyName"; exit 1; }

  if [ "${EXO_PROXY_SSL}" = "true" ]; then
    xmlstarlet ed -L \
      -s "/Server/Service/Connector" -t attr -n "scheme"    -v "https" \
      -s "/Server/Service/Connector" -t attr -n "secure"    -v "true"  \
      -s "/Server/Service/Connector" -t attr -n "proxyPort" -v "${EXO_PROXY_PORT}" \
      /opt/exo/conf/server.xml || { echo "ERROR: xmlstarlet failed configuring SSL proxy"; exit 1; }
    if [ "${EXO_PROXY_PORT}" = "443" ]; then
      add_in_exo_configuration "exo.base.url=https://${EXO_PROXY_VHOST}"
    else
      add_in_exo_configuration "exo.base.url=https://${EXO_PROXY_VHOST}:${EXO_PROXY_PORT}"
    fi
  else
    xmlstarlet ed -L \
      -s "/Server/Service/Connector" -t attr -n "scheme"    -v "http"  \
      -s "/Server/Service/Connector" -t attr -n "secure"    -v "false" \
      -s "/Server/Service/Connector" -t attr -n "proxyPort" -v "${EXO_PROXY_PORT}" \
      /opt/exo/conf/server.xml || { echo "ERROR: xmlstarlet failed configuring HTTP proxy"; exit 1; }
    if [ "${EXO_PROXY_PORT}" = "80" ]; then
      add_in_exo_configuration "exo.base.url=http://${EXO_PROXY_VHOST}"
    else
      add_in_exo_configuration "exo.base.url=http://${EXO_PROXY_VHOST}:${EXO_PROXY_PORT}"
    fi
  fi

  # Upload limits
  for _prop in \
    "exo.ecms.connector.drives.uploadLimit" \
    "exo.social.activity.uploadLimit" \
    "exo.social.composer.maxFileSizeInMB" \
    "wiki.attachment.uploadLimit" \
    "exo.uploadLimit"; do
    add_in_exo_configuration "${_prop}=${EXO_UPLOAD_MAX_FILE_SIZE}"
  done

  # Tomcat HTTP thread pool
  xmlstarlet ed -L \
    -s "/Server/Service/Connector" -t attr -n "maxThreads"        -v "${EXO_HTTP_THREAD_MAX}" \
    -s "/Server/Service/Connector" -t attr -n "minSpareThreads"   -v "${EXO_HTTP_THREAD_MIN}" \
    -s "/Server/Service/Connector" -t attr -n "maxHttpHeaderSize" -v "${EXO_HTTP_HEADER_MAX}" \
    /opt/exo/conf/server.xml || \
    { echo "ERROR: xmlstarlet failed configuring thread pool"; exit 1; }

  # Custom Tomcat valves/listeners via /etc/exo/host.yml
  if [ -e /etc/exo/host.yml ]; then
    echo "INFO: Applying custom valves/listeners from /etc/exo/host.yml"
    xmlstarlet ed -L \
      -d "/Server/Service/Engine/Host/Valve" \
      -d "/Server/Service/Engine/Host/Listener" \
      /opt/exo/conf/server.xml || \
      { echo "ERROR: xmlstarlet failed removing default host config"; exit 1; }

    _i=0
    while [ ${_i} -ge 0 ]; do
      _type=$(yq -r ".components[${_i}].type" /etc/exo/host.yml)
      [ "${_type}" = "null" ] && break
      _className=$(yq -r ".components[${_i}].className" /etc/exo/host.yml)
      echo "INFO: Adding ${_type} ${_className}"
      xmlstarlet ed -L \
        -s "/Server/Service/Engine/Host" -t elem -n "${_type}TMP" -v "" \
        -i "//${_type}TMP" -t attr -n "className" -v "${_className}" \
        /opt/exo/conf/server.xml || \
        { echo "ERROR: xmlstarlet failed adding ${_className}"; exit 1; }

      _j=0
      while [ ${_j} -ge 0 ]; do
        _attrName=$(yq -r ".components[${_i}].attributes[${_j}].name" /etc/exo/host.yml)
        [ "${_attrName}" = "null" ] && break
        _attrValue=$(yq -r ".components[${_i}].attributes[${_j}].value" /etc/exo/host.yml | tr -d "'")
        xmlstarlet ed -L \
          -i "//${_type}TMP" -t attr -n "${_attrName}" -v "${_attrValue}" \
          /opt/exo/conf/server.xml || \
          echo "WARNING: Could not set ${_attrName} on ${_className}"
        _j=$((_j + 1))
      done

      xmlstarlet ed -L -r "//${_type}TMP" -v "${_type}" /opt/exo/conf/server.xml || \
        { echo "ERROR: xmlstarlet failed renaming ${_type}TMP"; exit 1; }
      _i=$((_i + 1))
    done
  fi

  # Session timeout
  if [ "${EXO_SESSION_TIMEOUT}" -lt 1 ]; then
    echo "ERROR: EXO_SESSION_TIMEOUT must be >= 1 (got ${EXO_SESSION_TIMEOUT})"
    exit 1
  fi
  xmlstarlet ed -L \
    -N a="https://jakarta.ee/xml/ns/jakartaee" \
    -u "a:web-app/a:session-config/a:session-timeout" -v "${EXO_SESSION_TIMEOUT}" \
    /opt/exo/conf/web.xml || \
    { echo "ERROR: xmlstarlet failed setting session timeout"; exit 1; }

  # Mail
  add_in_exo_configuration "# Mail configuration"
  add_in_exo_configuration "exo.email.smtp.from=${EXO_MAIL_FROM}"
  add_in_exo_configuration "gatein.email.smtp.from=${EXO_MAIL_FROM}"
  add_in_exo_configuration "exo.email.smtp.host=${EXO_MAIL_SMTP_HOST}"
  add_in_exo_configuration "exo.email.smtp.port=${EXO_MAIL_SMTP_PORT}"
  add_in_exo_configuration "exo.email.smtp.starttls.enable=${EXO_MAIL_SMTP_STARTTLS}"
  if [ "${EXO_MAIL_SMTP_USERNAME:-}" = "-" ]; then
    add_in_exo_configuration "exo.email.smtp.auth=false"
    add_in_exo_configuration "#exo.email.smtp.username="
    add_in_exo_configuration "#exo.email.smtp.password="
  else
    add_in_exo_configuration "exo.email.smtp.auth=true"
    add_in_exo_configuration "exo.email.smtp.username=${EXO_MAIL_SMTP_USERNAME}"
    add_in_exo_configuration "exo.email.smtp.password=${EXO_MAIL_SMTP_PASSWORD}"
  fi
  if [ "${EXO_SMTP_SSL_ENABLED:-false}" = "false" ]; then
    add_in_exo_configuration "exo.email.smtp.socketFactory.port="
    add_in_exo_configuration "exo.email.smtp.socketFactory.class="
  else
    add_in_exo_configuration "exo.email.smtp.socketFactory.port=${EXO_MAIL_SSL_SOCKETFACTORY_PORT:-${EXO_MAIL_SMTP_PORT}}"
    add_in_exo_configuration "exo.email.smtp.socketFactory.class=javax.net.ssl.SSLSocketFactory"
  fi
  [ -n "${EXO_SMTP_SSL_PROTOCOLS:-}" ] && \
    add_in_exo_configuration "mail.smtp.ssl.protocols=${EXO_SMTP_SSL_PROTOCOLS}"

  # JMX
  if [ "${EXO_JMX_ENABLED}" = "true" ] && [ "${EXO_JMX_USERNAME:-}" != "-" ]; then
    if [ "${EXO_JMX_PASSWORD:-}" = "-" ]; then
      EXO_JMX_PASSWORD="$(tr -dc '[:alnum:]' < /dev/urandom | dd bs=2 count=6 2>/dev/null)"
    fi
    echo "${EXO_JMX_USERNAME} ${EXO_JMX_PASSWORD}" > /opt/exo/conf/jmxremote.password
    echo "${EXO_JMX_USERNAME} readwrite"            > /opt/exo/conf/jmxremote.access
    chmod 600 /opt/exo/conf/jmxremote.password /opt/exo/conf/jmxremote.access
  fi

  # Access log valve
  if [ "${EXO_ACCESS_LOG_ENABLED}" = "true" ]; then
    xmlstarlet ed -L \
      -s "/Server/Service/Engine/Host" -t elem -n "ValveTMP" -v "" \
      -i "//ValveTMP" -t attr -n "className"       -v "org.apache.catalina.valves.AccessLogValve" \
      -i "//ValveTMP" -t attr -n "pattern"         -v "combined" \
      -i "//ValveTMP" -t attr -n "directory"       -v "logs" \
      -i "//ValveTMP" -t attr -n "prefix"          -v "access" \
      -i "//ValveTMP" -t attr -n "suffix"          -v ".log" \
      -i "//ValveTMP" -t attr -n "rotatable"       -v "true" \
      -i "//ValveTMP" -t attr -n "renameOnRotate"  -v "true" \
      -i "//ValveTMP" -t attr -n "fileDateFormat"  -v ".yyyy-MM-dd" \
      -r "//ValveTMP" -v Valve \
      /opt/exo/conf/server.xml || \
      { echo "ERROR: xmlstarlet failed adding AccessLogValve"; exit 1; }
  fi

  # Gzip
  if [ "${EXO_GZIP_ENABLED}" = "true" ]; then
    xmlstarlet ed -L \
      -u "/Server/Service/Connector/@compression" -v "on" \
      /opt/exo/conf/server.xml || \
      { echo "ERROR: xmlstarlet failed enabling gzip"; exit 1; }
  fi

  # Connection timeout
  xmlstarlet ed -L \
    -u "/Server/Service/Connector/@connectionTimeout" -v "${EXO_CONNECTION_TIMEOUT:-20000}" \
    /opt/exo/conf/server.xml || \
    { echo "ERROR: xmlstarlet failed setting connectionTimeout"; exit 1; }

  # Elasticsearch
  add_in_exo_configuration "# Elasticsearch configuration"
  add_in_exo_configuration "exo.es.embedded.enabled=false"
  add_in_exo_configuration "exo.es.search.server.url=${EXO_ES_URL}"
  add_in_exo_configuration "exo.es.index.server.url=${EXO_ES_URL}"
  if [ "${EXO_ES_USERNAME:-}" != "-" ]; then
    add_in_exo_configuration "exo.es.index.server.username=${EXO_ES_USERNAME}"
    add_in_exo_configuration "exo.es.index.server.password=${EXO_ES_PASSWORD}"
    add_in_exo_configuration "exo.es.search.server.username=${EXO_ES_USERNAME}"
    add_in_exo_configuration "exo.es.search.server.password=${EXO_ES_PASSWORD}"
  else
    add_in_exo_configuration "#exo.es.index.server.username="
    add_in_exo_configuration "#exo.es.index.server.password="
    add_in_exo_configuration "#exo.es.search.server.username="
    add_in_exo_configuration "#exo.es.search.server.password="
  fi
  add_in_exo_configuration "exo.es.indexing.replica.number.default=${EXO_ES_INDEX_REPLICA_NB}"
  add_in_exo_configuration "exo.es.indexing.shard.number.default=${EXO_ES_INDEX_SHARD_NB}"

  # Registration
  if [ "${EXO_REGISTRATION}" = "false" ]; then
    add_in_exo_configuration "# Registration"
    add_in_exo_configuration "exo.registration.skip=true"
  fi

  # Chat
  add_in_chat_configuration "# eXo Chat server configuration"
  add_in_chat_configuration "chatPassPhrase=${EXO_CHAT_SERVER_PASSPHRASE}"
  add_in_chat_configuration "teamAdminGroup=/platform/users"
  add_in_chat_configuration "chatServerUrl=${EXO_CHAT_SERVER_URL}/chatServer"
  add_in_chat_configuration "# eXo Chat client configuration"
  add_in_chat_configuration "chatIntervalChat=3000"
  add_in_chat_configuration "chatIntervalSession=60000"
  add_in_chat_configuration "chatIntervalStatus=20000"
  add_in_chat_configuration "chatIntervalNotif=3000"
  add_in_chat_configuration "chatIntervalUsers=5000"
  add_in_chat_configuration "chatTokenValidity=30000"

  if [ "${EXO_CHAT_SERVER_STANDALONE}" = "false" ]; then
    add_in_chat_configuration "# eXo Chat mongodb configuration"
    add_in_chat_configuration "dbServerHosts=${EXO_MONGO_HOST}:${EXO_MONGO_PORT}"
    add_in_chat_configuration "dbName=${EXO_MONGO_DB_NAME}"
    if [ "${EXO_MONGO_USERNAME:-}" = "-" ]; then
      add_in_chat_configuration "dbAuthentication=false"
      add_in_chat_configuration "#dbUser="
      add_in_chat_configuration "#dbPassword="
    else
      add_in_chat_configuration "dbAuthentication=true"
      add_in_chat_configuration "dbUser=${EXO_MONGO_USERNAME}"
      add_in_chat_configuration "dbPassword=${EXO_MONGO_PASSWORD}"
    fi
    add_in_chat_configuration "chatCronNotifCleanup=0 0 * * * ?"
    add_in_chat_configuration "chatReadDays=30"
  else
    if [ -f /opt/exo/addons/statuses/exo-chat.status ]; then
      EXO_CHAT_VERSION="$(jq -r ".version" /opt/exo/addons/statuses/exo-chat.status)"
      echo "WARN: Replacing exo-chat:${EXO_CHAT_VERSION} with exo-chat-client:${EXO_CHAT_VERSION} (standalone mode)"
      EXO_ADDONS_REMOVE_LIST="${EXO_ADDONS_REMOVE_LIST:-},exo-chat"
      EXO_ADDONS_LIST="${EXO_ADDONS_LIST:-},exo-chat-client:${EXO_CHAT_VERSION}"
    fi
    [ -z "${EXO_CHAT_SERVICE_URL}" ] && EXO_CHAT_SERVICE_URL="http://localhost:8080"
    add_in_chat_configuration "# eXo Chat server configuration"
    add_in_chat_configuration "standaloneChatServer=true"
    add_in_chat_configuration "chatServiceUrl=${EXO_CHAT_SERVICE_URL}"
  fi

  # Rewards / wallet
  add_in_exo_configuration "# Rewards configuration"
  add_in_exo_configuration "exo.wallet.admin.key=${EXO_REWARDS_WALLET_ADMIN_KEY}"
  [ -n "${EXO_REWARDS_WALLET_ACCESS_PERMISSION:-}" ] && \
    add_in_exo_configuration "exo.wallet.accessPermission=${EXO_REWARDS_WALLET_ACCESS_PERMISSION}"
  add_in_exo_configuration "exo.wallet.blockchain.networkId=${EXO_REWARDS_WALLET_NETWORK_ID}"
  add_in_exo_configuration "exo.wallet.blockchain.network.http=${EXO_REWARDS_WALLET_NETWORK_ENDPOINT_HTTP}"
  add_in_exo_configuration "exo.wallet.blockchain.network.websocket=${EXO_REWARDS_WALLET_NETWORK_ENDPOINT_WEBSOCKET}"
  add_in_exo_configuration "exo.wallet.blockchain.token.address=${EXO_REWARDS_WALLET_TOKEN_ADDRESS}"
  [ -n "${EXO_REWARDS_WALLET_ADMIN_PRIVATE_KEY:-}" ] && \
    add_in_exo_configuration "exo.wallet.admin.privateKey=${EXO_REWARDS_WALLET_ADMIN_PRIVATE_KEY}"
  [ -n "${EXO_REWARDS_WALLET_NETWORK_CRYPTOCURRENCY:-}" ] && \
    add_in_exo_configuration "exo.wallet.blockchain.network.cryptocurrency=${EXO_REWARDS_WALLET_NETWORK_CRYPTOCURRENCY}"
  [ -n "${EXO_REWARDS_WALLET_TOKEN_SYMBOL:-}" ] && \
    add_in_exo_configuration "exo.wallet.blockchain.token.symbol=${EXO_REWARDS_WALLET_TOKEN_SYMBOL}"

  # Agenda
  add_in_exo_configuration "# Agenda configuration"
  add_in_exo_configuration "exo.agenda.google.connector.enabled=${EXO_AGENDA_GOOGLE_CONNECTOR_ENABLED}"
  add_in_exo_configuration "exo.agenda.google.connector.key=${EXO_AGENDA_GOOGLE_CONNECTOR_CLIENT_API_KEY}"
  add_in_exo_configuration "exo.agenda.office.connector.enabled=${EXO_AGENDA_OFFICE_CONNECTOR_ENABLED}"
  add_in_exo_configuration "exo.agenda.office.connector.key=${EXO_AGENDA_OFFICE_CONNECTOR_CLIENT_API_KEY}"

  # Remember-me token
  add_in_exo_configuration "exo.token.rememberme.expiration.value=${EXO_TOKEN_REMEMBERME_EXPIRATION_VALUE}"
  add_in_exo_configuration "exo.token.rememberme.expiration.unit=${EXO_TOKEN_REMEMBERME_EXPIRATION_UNIT}"

  touch /opt/exo/_done.configuration
  echo "INFO: First-time configuration complete."
fi

# ---------------------------------------------------------------------------
# Self-signed certificate import
# ---------------------------------------------------------------------------
_custKeyStoreDir=/opt/exo/.custkeystore
_custKeyStoreFile=${_custKeyStoreDir}/exo-truststore
_hashStoreDir=/opt/exo/.cert_hashes
_keytoolPass="${EXO_CACERTS_STOREPASS}"

if [ -z "${EXO_SELFSIGNEDCERTS_HOSTS:-}" ]; then
  echo "INFO: No self-signed certificates to import (EXO_SELFSIGNEDCERTS_HOSTS not set)."
else
  echo "INFO: Importing self-signed certificates ..."
  mkdir -p "${_custKeyStoreDir}" "${_hashStoreDir}"

  if [ ! -f "${_custKeyStoreFile}" ]; then
    cp -f "${EXO_CACERTS:-$JAVA_HOME/lib/security/cacerts}" "${_custKeyStoreFile}"
    echo "INFO: Custom truststore initialised."
  fi

  echo "${EXO_SELFSIGNEDCERTS_HOSTS}" | tr ',' '\n' | while read -r _host; do
    [ -z "${_host}" ] && continue
    _sslPort=':443'
    echo "${_host}" | grep -q ':' && _sslPort=''
    _sanitized=$(echo "${_host}" | cut -d: -f1)
    _tmpCert="/tmp/${_sanitized}.crt"
    _hashFile="${_hashStoreDir}/${_sanitized}.hash"

    echo "INFO: Fetching certificate from ${_host}${_sslPort} ..."
    echo -n | openssl s_client -connect "${_host}${_sslPort}" 2>/dev/null \
      | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "${_tmpCert}"

    if [ ! -s "${_tmpCert}" ]; then
      rm -f "${_tmpCert}"
      if [ "${EXO_SELFSIGNEDCERTS_STRICT_MODE:-false}" = "false" ] && [ -f "${_hashFile}" ]; then
        echo "WARNING: Cannot reach ${_host}${_sslPort} – using cached certificate."
      else
        echo "ERROR: Cannot fetch certificate for ${_host}${_sslPort} (strict mode). Aborting!"
        exit 1
      fi
      continue
    fi

    _hash=$(openssl x509 -in "${_tmpCert}" -noout -sha256 -fingerprint \
              | sed 's/://g' | awk -F= '{print $2}')

    if [ -f "${_hashFile}" ] && [ "${_hash}" = "$(cat "${_hashFile}")" ]; then
      echo "INFO: Certificate for ${_host} unchanged – skipping."
      rm -f "${_tmpCert}"
      continue
    fi

    keytool -list -keystore "${_custKeyStoreFile}" -storepass "${_keytoolPass}" \
      -alias "${_sanitized}" > /dev/null 2>&1 && \
      keytool -delete -alias "${_sanitized}" -keystore "${_custKeyStoreFile}" \
        -storepass "${_keytoolPass}" -noprompt 2>/dev/null

    keytool -import -trustcacerts -noprompt \
      -keystore "${_custKeyStoreFile}" -storepass "${_keytoolPass}" \
      -alias "${_sanitized}" -file "${_tmpCert}" || \
      { echo "ERROR: Failed to import certificate for ${_host}"; exit 1; }

    echo "${_hash}" > "${_hashFile}"
    rm -f "${_tmpCert}"
    echo "INFO: Certificate for ${_host} imported."
  done
fi

# Configure JVM truststore if custom CA was imported or provided
if [ -f "${_custKeyStoreFile}" ]; then
  _TRUSTSTORE="${_custKeyStoreFile}"
  _TRUSTSTORE_PASS="${EXO_CACERTS_STOREPASS}"
elif [ -n "${EXO_CACERTS}" ] && [ -f "${EXO_CACERTS}" ]; then
  _TRUSTSTORE="${EXO_CACERTS}"
  _TRUSTSTORE_PASS="${EXO_CACERTS_STOREPASS}"
fi

if [ -n "${_TRUSTSTORE:-}" ]; then
  _TS_OPTS="-Djavax.net.ssl.trustStore=${_TRUSTSTORE} -Djavax.net.ssl.trustStorePassword=${_TRUSTSTORE_PASS}"
  export ADDONSMGR_PROPERTIES="${ADDONSMGR_PROPERTIES:-} ${_TS_OPTS}"
  CATALINA_OPTS="${CATALINA_OPTS:-} ${_TS_OPTS}"
fi

# ---------------------------------------------------------------------------
# One-time add-on removal (guarded by sentinel file)
# ---------------------------------------------------------------------------
if [ ! -f /opt/exo/_done.addons_removal ]; then
  if [ -z "${EXO_ADDONS_REMOVE_LIST:-}" ]; then
    echo "INFO: No add-ons to remove."
  else
    echo "INFO: Removing add-ons: ${EXO_ADDONS_REMOVE_LIST}"
    echo "${EXO_ADDONS_REMOVE_LIST}" | tr ',' '\n' | while read -r _addon; do
      [ -z "${_addon}" ] && continue
      "${EXO_APP_DIR}/addon" uninstall "${_addon}" || \
        { echo "ERROR: Failed to uninstall addon ${_addon}"; exit 1; }
    done
  fi
  touch /opt/exo/_done.addons_removal
fi

# ---------------------------------------------------------------------------
# One-time add-on installation (guarded by sentinel file)
# ---------------------------------------------------------------------------
if [ -f /opt/exo/_done.addons ]; then
  echo "INFO: Add-on installation already done – skipping."
else
  _ADDON_MGR_OPTIONS=""
  [ -n "${EXO_ADDONS_CATALOG_URL:-}" ]         && _ADDON_MGR_OPTION_CATALOG="--catalog=${EXO_ADDONS_CATALOG_URL}"
  [ -n "${EXO_PATCHES_CATALOG_URL:-}" ]         && _ADDON_MGR_OPTION_PATCHES_CATALOG="--catalog=${EXO_PATCHES_CATALOG_URL}"
  [ "${EXO_ADDONS_CONFLICT_MODE:-}" = "overwrite" ] || [ "${EXO_ADDONS_CONFLICT_MODE:-}" = "ignore" ] && \
    _ADDON_MGR_OPTIONS="${_ADDON_MGR_OPTIONS} --conflict=${EXO_ADDONS_CONFLICT_MODE}"
  [ "${EXO_ADDONS_NOCOMPAT_MODE:-false}" = "true" ] && \
    _ADDON_MGR_OPTIONS="${_ADDON_MGR_OPTIONS} --no-compat"

  if [ -z "${EXO_ADDONS_LIST:-}" ]; then
    echo "INFO: No add-ons to install."
  else
    echo "INFO: Installing add-ons ..."
    _first=true
    echo "${EXO_ADDONS_LIST}" | tr ',' '\n' | while read -r _addon; do
      [ -z "${_addon}" ] && continue
      _extra_opts=""
      if [ "${_first}" = "true" ]; then
        _extra_opts="--no-cache"
        _first=false
      fi
      timeout "${EXO_ADDONS_INSTALL_TIMEOUT}" \
        "${EXO_APP_DIR}/addon" install ${_ADDON_MGR_OPTIONS:-} ${_ADDON_MGR_OPTION_CATALOG:-} \
          "${_addon}" --force --batch-mode ${_extra_opts} || \
        { echo "ERROR: Failed to install addon ${_addon}"; exit 1; }
    done
  fi
  touch /opt/exo/_done.addons
fi

# ---------------------------------------------------------------------------
# One-time patch installation
# ---------------------------------------------------------------------------
if [ -f /opt/exo/_done.patches ]; then
  echo "INFO: Patch installation already done – skipping."
else
  if [ -z "${EXO_PATCHES_LIST:-}" ]; then
    echo "INFO: No patches to install."
  else
    if [ -z "${_ADDON_MGR_OPTION_PATCHES_CATALOG:-}" ]; then
      echo "ERROR: EXO_PATCHES_CATALOG_URL must be set when using EXO_PATCHES_LIST"
      exit 1
    fi
    echo "INFO: Installing patches ..."
    echo "${EXO_PATCHES_LIST}" | tr ',' '\n' | while read -r _patch; do
      [ -z "${_patch}" ] && continue
      "${EXO_APP_DIR}/addon" install --conflict=overwrite \
        "${_ADDON_MGR_OPTION_PATCHES_CATALOG:-}" "${_patch}" --force --batch-mode || \
        { echo "ERROR: Failed to install patch ${_patch}"; exit 1; }
    done
  fi
  touch /opt/exo/_done.patches
fi

# ---------------------------------------------------------------------------
# Rotate Chat passphrase on every start
# ---------------------------------------------------------------------------
if [ -f /etc/exo/chat.properties ] && [ "${EXO_CHAT_SERVER_STANDALONE:-false}" = "false" ]; then
  sed -i "s/^chatPassPhrase=.*$/chatPassPhrase=$(tr -dc '[:alnum:]' < /dev/urandom | dd bs=4 count=6 2>/dev/null)/" \
    /etc/exo/chat.properties
fi

# ---------------------------------------------------------------------------
# JVM tuning & security flags
# ---------------------------------------------------------------------------
CATALINA_OPTS="${CATALINA_OPTS:-} -Dexo.license.path=/etc/exo"
CATALINA_OPTS="${CATALINA_OPTS} -Dlog4j2.formatMsgNoLookups=true"
CATALINA_OPTS="${CATALINA_OPTS} -Djava.security.egd=file:/dev/./urandom"

# Debug mode
if [ "${EXO_DEBUG_ENABLED:-false}" = "true" ]; then
  CATALINA_OPTS="${CATALINA_OPTS} -agentlib:jdwp=transport=dt_socket,address=*:${EXO_DEBUG_PORT:-8000},server=y,suspend=n"
  echo "INFO: Remote debug enabled on port ${EXO_DEBUG_PORT:-8000}"
fi

# LDAP connection pool
CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.jndi.ldap.connect.pool.timeout=${EXO_LDAP_POOL_TIMEOUT}"
CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.jndi.ldap.connect.pool.maxsize=${EXO_LDAP_POOL_MAX_SIZE}"
[ -n "${EXO_LDAP_POOL_DEBUG:-}" ] && \
  CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.jndi.ldap.connect.pool.debug=${EXO_LDAP_POOL_DEBUG}"

# JMX
if [ "${EXO_JMX_ENABLED}" = "true" ]; then
  CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.management.jmxremote=true"
  CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.management.jmxremote.ssl=false"
  CATALINA_OPTS="${CATALINA_OPTS} -Djava.rmi.server.hostname=${EXO_JMX_RMI_SERVER_HOSTNAME}"
  CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.management.jmxremote.port=${EXO_JMX_RMI_REGISTRY_PORT}"
  CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.management.jmxremote.rmi.port=${EXO_JMX_RMI_SERVER_PORT}"
  if [ "${EXO_JMX_USERNAME:-}" = "-" ]; then
    CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.management.jmxremote.authenticate=false"
  else
    CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.management.jmxremote.authenticate=true"
    CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.management.jmxremote.password.file=/opt/exo/conf/jmxremote.password"
    CATALINA_OPTS="${CATALINA_OPTS} -Dcom.sun.management.jmxremote.access.file=/opt/exo/conf/jmxremote.access"
  fi
fi

# GC logging
if [ "${EXO_JVM_LOG_GC_ENABLED}" = "true" ]; then
  _GC_LOG="${EXO_LOG_DIR}/platform-gc.log"
  _GC_OPTS="-Xlog:gc=info:file=${_GC_LOG}:time"
  echo "INFO: GC logging enabled → ${_GC_LOG}"
  CATALINA_OPTS="${CATALINA_OPTS} ${_GC_OPTS}"
  mkdir -p "${EXO_LOG_DIR}/platform-gc"
  if [ -f "${_GC_LOG}" ]; then
    _archive="${EXO_LOG_DIR}/platform-gc/platform-gc_$(date -u +%F_%H%M%S%z).log"
    mv "${_GC_LOG}" "${_archive}"
    echo "INFO: Previous GC log archived to ${_archive}"
  fi
fi

# ---------------------------------------------------------------------------
# Ensure data directories exist at runtime
# ---------------------------------------------------------------------------
[ ! -d "${EXO_DATA_DIR}" ]         && mkdir -p "${EXO_DATA_DIR}"
[ ! -d "${EXO_FILE_STORAGE_DIR}" ] && mkdir -p "${EXO_FILE_STORAGE_DIR}"

# ---------------------------------------------------------------------------
# Service readiness checks
# ---------------------------------------------------------------------------
_wait_for_service() {
  local _label="$1" _host="$2" _port="$3" _timeout="$4"
  echo "INFO: Waiting for ${_label} at ${_host}:${_port} (timeout: ${_timeout}s) ..."
  wait-for-it -h "${_host}" -p "${_port}" -t "${_timeout}" -- true 2>/dev/null || \
  { echo "ERROR: ${_label} not reachable at ${_host}:${_port} within ${_timeout}s – aborting!"; exit 1; }
  echo "INFO: ${_label} is up."
}

case "${EXO_DB_TYPE}" in
  mysql|pgsql|postgres|postgresql)
    _wait_for_service "Database (${EXO_DB_TYPE})" "${EXO_DB_HOST}" "${EXO_DB_PORT}" "${EXO_DB_TIMEOUT}"
    ;;
esac

if [ -f /opt/exo/addons/statuses/exo-chat.status ] && [ "${EXO_CHAT_SERVER_STANDALONE:-false}" = "false" ]; then
  _wait_for_service "MongoDB" "${EXO_MONGO_HOST}" "${EXO_MONGO_PORT}" "${EXO_MONGO_TIMEOUT}"
fi

_wait_for_service "Elasticsearch" "${EXO_ES_HOST}" "${EXO_ES_PORT}" "${EXO_ES_TIMEOUT}"

if [ "${EXO_WAIT_FOR_MATRIX}" = "true" ]; then
  _wait_for_service "Matrix" "${EXO_MATRIX_HOST}" "${EXO_MATRIX_PORT}" "${EXO_MATRIX_TIMEOUT}"
fi

set +u  # allow unbound check off for final optional step

# ---------------------------------------------------------------------------
# Guard: reject empty exo.properties if strict mode is on
# ---------------------------------------------------------------------------
if "${EXO_STRICT_CHECK_CONF:-false}"; then
  check_exo_properties
fi
