# eXo Platform Enterprise – Docker Image

[![Build Status](https://github.com/exo-docker/exo-enterprise/actions/workflows/publish.yaml/badge.svg)](https://github.com/exo-docker/exo-enterprise/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/exoplatform/exo-enterprise)](https://hub.docker.com/r/exoplatform/exo-enterprise)

Docker image for [eXo Platform](https://www.exoplatform.com) Enterprise Edition.

---

## Quick start

```bash
docker run -d --name exo \
  -p 80:8080 \
  -e EXO_DB_TYPE=pgsql \
  -e EXO_DB_HOST=db \
  -e EXO_DB_PASSWORD=secret \
  exoplatform/exo-enterprise
```

---

## Build

```bash
# Default version
docker build -t exoplatform/exo-enterprise .

# Specific version
docker build --build-arg EXO_VERSION=7.2.0 -t exoplatform/exo-enterprise:7.2.0 .

# Custom download URL
docker build \
  --build-arg DOWNLOAD_URL=https://my.server/platform-7.2.0.zip \
  --build-arg DOWNLOAD_USER=user:password \
  -t exoplatform/exo-enterprise .
```

---

## Configuration reference

All configuration is driven by environment variables passed to `docker run` or your Compose file.

### Proxy

| Variable | Default | Description |
|---|---|---|
| `EXO_PROXY_VHOST` | `localhost` | Virtual hostname seen by the browser |
| `EXO_PROXY_SSL` | `true` | `true` → HTTPS scheme; `false` → HTTP |
| `EXO_PROXY_PORT` | `443` / `80` | Proxy port (auto-inferred from SSL) |

### Database

| Variable | Default | Description |
|---|---|---|
| `EXO_DB_TYPE` | `mysql` | `mysql` \| `pgsql` \| `hsqldb` |
| `EXO_DB_HOST` | `db` | Database hostname |
| `EXO_DB_PORT` | `3306` / `5432` | Database port |
| `EXO_DB_NAME` | `exo` | Database name |
| `EXO_DB_USER` | `exo` | Database user |
| `EXO_DB_PASSWORD` | **required** | Database password |
| `EXO_DB_TIMEOUT` | `60` | Seconds to wait for DB on startup |
| `EXO_DB_POOL_IDM_INIT_SIZE` | `5` | IDM pool initial size |
| `EXO_DB_POOL_IDM_MAX_SIZE` | `20` | IDM pool max size |
| `EXO_DB_POOL_JCR_INIT_SIZE` | `5` | JCR pool initial size |
| `EXO_DB_POOL_JCR_MAX_SIZE` | `20` | JCR pool max size |
| `EXO_DB_POOL_JPA_INIT_SIZE` | `5` | JPA pool initial size |
| `EXO_DB_POOL_JPA_MAX_SIZE` | `20` | JPA pool max size |
| `EXO_DB_MYSQL_USE_SSL` | `false` | Enable SSL for MySQL connections |

### Storage

| Variable | Default | Description |
|---|---|---|
| `EXO_DATA_DIR` | `/srv/exo` | Root data directory |
| `EXO_JCR_STORAGE_DIR` | `$EXO_DATA_DIR/jcr/values` | JCR binary storage path |
| `EXO_FILE_STORAGE_DIR` | `$EXO_DATA_DIR/files` | File service storage path |
| `EXO_FILE_STORAGE_RETENTION` | `30` | Orphan file retention in days |
| `EXO_JCR_FS_STORAGE_ENABLED` | _(unset)_ | Explicitly enable/disable JCR FS storage |
| `EXO_FILE_STORAGE_TYPE` | _(unset)_ | Override file storage backend type |

### Elasticsearch

| Variable | Default | Description |
|---|---|---|
| `EXO_ES_HOST` | `localhost` | Elasticsearch hostname |
| `EXO_ES_PORT` | `9200` | Elasticsearch port |
| `EXO_ES_SCHEME` | `http` | `http` or `https` |
| `EXO_ES_USERNAME` | `-` | ES username (`-` = anonymous) |
| `EXO_ES_PASSWORD` | `-` | ES password |
| `EXO_ES_TIMEOUT` | `60` | Seconds to wait for ES on startup |
| `EXO_ES_INDEX_REPLICA_NB` | `1` | Default index replica count |
| `EXO_ES_INDEX_SHARD_NB` | `5` | Default index shard count |

### Mail

| Variable | Default | Description |
|---|---|---|
| `EXO_MAIL_FROM` | `noreply@exoplatform.com` | Sender address |
| `EXO_MAIL_SMTP_HOST` | `localhost` | SMTP host |
| `EXO_MAIL_SMTP_PORT` | `25` | SMTP port |
| `EXO_MAIL_SMTP_STARTTLS` | `false` | Enable STARTTLS |
| `EXO_MAIL_SMTP_USERNAME` | `-` | SMTP user (`-` = anonymous) |
| `EXO_MAIL_SMTP_PASSWORD` | `-` | SMTP password |
| `EXO_SMTP_SSL_ENABLED` | `false` | Enable SSL socket factory |
| `EXO_SMTP_SSL_PROTOCOLS` | _(unset)_ | Explicit TLS version, e.g. `TLSv1.2` |

### JVM

| Variable | Default | Description |
|---|---|---|
| `EXO_JVM_SIZE_MIN` | _(from base)_ | `-Xms` value |
| `EXO_JVM_SIZE_MAX` | _(from base)_ | `-Xmx` value |
| `EXO_JVM_LOG_GC_ENABLED` | `false` | Enable GC logging |

### JMX

| Variable | Default | Description |
|---|---|---|
| `EXO_JMX_ENABLED` | `true` | Enable JMX remote |
| `EXO_JMX_RMI_REGISTRY_PORT` | `10001` | JMX registry port |
| `EXO_JMX_RMI_SERVER_PORT` | `10002` | JMX RMI server port |
| `EXO_JMX_RMI_SERVER_HOSTNAME` | `localhost` | Advertised hostname |
| `EXO_JMX_USERNAME` | `-` | JMX user (`-` = no auth) |
| `EXO_JMX_PASSWORD` | `-` | JMX password (auto-generated if unset) |

### Chat / MongoDB

| Variable | Default | Description |
|---|---|---|
| `EXO_CHAT_SERVER_STANDALONE` | `false` | Use external chat server |
| `EXO_CHAT_SERVER_URL` | `http://localhost:8080` | Internal chat server URL |
| `EXO_CHAT_SERVICE_URL` | _(unset)_ | External chat service URL (standalone mode) |
| `EXO_CHAT_SERVER_PASSPHRASE` | `something2change` | **Change in production!** |
| `EXO_MONGO_HOST` | `mongo` | MongoDB hostname |
| `EXO_MONGO_PORT` | `27017` | MongoDB port |
| `EXO_MONGO_DB_NAME` | `chat` | MongoDB database name |
| `EXO_MONGO_USERNAME` | `-` | MongoDB user (`-` = no auth) |
| `EXO_MONGO_PASSWORD` | `-` | MongoDB password |
| `EXO_MONGO_TIMEOUT` | `60` | Seconds to wait for MongoDB on startup |

### Matrix (optional)

| Variable | Default | Description |
|---|---|---|
| `EXO_WAIT_FOR_MATRIX` | `false` | Block startup until Matrix is reachable |
| `EXO_MATRIX_HOST` | `matrix` | Matrix hostname |
| `EXO_MATRIX_PORT` | `8008` | Matrix port |
| `EXO_MATRIX_TIMEOUT` | `30` | Wait timeout in seconds |

### Add-ons & Patches

| Variable | Default | Description |
|---|---|---|
| `EXO_ADDONS_LIST` | _(unset)_ | Comma-separated list of add-ons to install |
| `EXO_ADDONS_REMOVE_LIST` | _(unset)_ | Comma-separated list of add-ons to remove |
| `EXO_ADDONS_CATALOG_URL` | _(unset)_ | Override add-on manager catalog URL |
| `EXO_ADDONS_CONFLICT_MODE` | _(unset)_ | `overwrite` or `ignore` |
| `EXO_ADDONS_NOCOMPAT_MODE` | `false` | Skip compatibility checks |
| `EXO_ADDONS_INSTALL_TIMEOUT` | `120` | Per-add-on install timeout (seconds) |
| `EXO_PATCHES_LIST` | _(unset)_ | Comma-separated list of patches to apply |
| `EXO_PATCHES_CATALOG_URL` | _(unset)_ | Required when `EXO_PATCHES_LIST` is set |

### Miscellaneous

| Variable | Default | Description |
|---|---|---|
| `EXO_REGISTRATION` | `true` | Allow public self-registration |
| `EXO_GZIP_ENABLED` | `true` | Enable HTTP gzip compression |
| `EXO_ACCESS_LOG_ENABLED` | `false` | Enable Tomcat access log |
| `EXO_SESSION_TIMEOUT` | `30` | HTTP session timeout in minutes |
| `EXO_CONNECTION_TIMEOUT` | `20000` | Tomcat connector timeout in ms |
| `EXO_FILE_UMASK` | `0022` | Umask for file creation |
| `EXO_DEBUG_ENABLED` | `false` | Enable JDWP remote debug |
| `EXO_DEBUG_PORT` | `8000` | JDWP listen port |
| `EXO_STRICT_CHECK_CONF` | `false` | Abort if `exo.properties` is empty |
| `EXO_CACERTS` | _(unset)_ | Path to a custom JDK truststore |
| `EXO_CACERTS_STOREPASS` | `changeit` | Truststore password |
| `EXO_SELFSIGNEDCERTS_HOSTS` | _(unset)_ | Comma-separated `host:port` list for self-signed cert import |
| `EXO_SELFSIGNEDCERTS_STRICT_MODE` | `false` | Abort if a cert cannot be fetched |
| `EXO_CLUSTER_NODE_NAME` | _(unset)_ | Tomcat jvmRoute for cluster load-balancing |

### Secret injection via files

Any environment variable can be provided via a Docker secret or mounted file using the pattern:

```
EXO_SEC_<VARIABLE_NAME>_FILE=/run/secrets/db_password
```

For example, `EXO_SEC_DB_PASSWORD_FILE=/run/secrets/db_password` will read the file and export it as `EXO_DB_PASSWORD`. The direct environment variable takes precedence unless you also set `EXO_SEC_<VAR>_FILE_FORCE=true`.

---

## Persistent volumes

Mount these paths to preserve data across container restarts:

| Path | Purpose |
|---|---|
| `/srv/exo` | Application data (JCR, files) |
| `/etc/exo/codec` | Encryption codec keys |
| `/var/log/exo` | Log files |

---

## Development / test stacks

Pre-configured Compose stacks are in `test/`:

```bash
# PostgreSQL
docker compose -f test/docker-compose-71-pgsql.yml up

# MySQL
docker compose -f test/docker-compose-71-mysql.yml up
```

The mail UI (Mailpit) is available at **http://localhost:8025**.

---

## License

[LGPL v2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html)
