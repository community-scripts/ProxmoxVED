#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Blarm1959
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Dispatcharr/Dispatcharr

APP="Dispatcharr"
var_tags="${var_tags:-}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
  export APT_LISTCHANGES_NO_MAIL=1

  APP_DIR="/opt/dispatcharr"

  if [[ ! -d "$APP_DIR" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  DEFAULT_BACKUP_RETENTION=3
  VARS_FILE="/root/.dispatcharr_vars"
  VERSION_FILE="/root/.dispatcharr"
  CURRENT_VERSION=""

  BACKUP_RETENTION="$DEFAULT_BACKUP_RETENTION"

  VALID_DOPTS=("BR" "IV" "BO")
  DOPT="${DOPT:-}"

  if [ ! -z "$DOPT" ]; then
    valid_flag="false"
    for v in "${VALID_DOPTS[@]}"; do
      if [[ "$DOPT" == "$v" ]]; then
        valid_flag="true"
        break
      fi
    done
    if [[ "$valid_flag" != "true" ]]; then
      msg_warn "Invalid DOPT=${DOPT}. Valid options are: BR (Backup Retention), IV (Ignore Version), BO (Build-Only)."
      exit 1
    fi
  fi

  POSTGRES_DB="dispatcharr"
  POSTGRES_USER="dispatch"
  POSTGRES_PASSWORD=""
  CREDS_FILE="/root/dispatcharr.creds"
  if [ -f "${CREDS_FILE}" ]; then
    POSTGRES_USER=$(grep -E '^Dispatcharr Database User:' "${CREDS_FILE}" | awk -F': ' '{print $2}' | tr -d '\r[:space:]')
    POSTGRES_PASSWORD=$(grep -E '^Dispatcharr Database Password:' "${CREDS_FILE}" | awk -F': ' '{print $2}' | tr -d '\r[:space:]')
    POSTGRES_DB=$(grep -E '^Dispatcharr Database Name:' "${CREDS_FILE}" | awk -F': ' '{print $2}' | tr -d '\r[:space:]')
    if [ -z "${POSTGRES_USER}" ] || [ -z "${POSTGRES_PASSWORD}" ] || [ -z "${POSTGRES_DB}" ]; then
      msg_error "One or more PostgreSQL credentials are missing in ${CREDS_FILE}."
      echo "Expected lines:"
      echo "  Dispatcharr Database User: ..."
      echo "  Dispatcharr Database Password: ..."
      echo "  Dispatcharr Database Name: ..."
      exit 1
    fi
  else
    msg_error "Postgres credentials file ${CREDS_FILE} not found!"
    exit 1
  fi
  if ! PGPASSWORD="${POSTGRES_PASSWORD}" \
      psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -h localhost -q -c "SELECT 1;" >/dev/null 2>&1; then
    msg_error "PostgreSQL login failed — credentials in ${CREDS_FILE} may be invalid."
    exit 1
  fi

  if [ -f "$VARS_FILE" ]; then
    . "$VARS_FILE"
  fi

  if [[ "${BACKUP_RETENTION}" =~ ^[Aa][Ll][Ll]$ ]]; then
    BACKUP_RETENTION="ALL"
  elif ! [[ "${BACKUP_RETENTION}" =~ ^[0-9]+$ ]] || [ "${BACKUP_RETENTION}" -le 0 ]; then
    BACKUP_RETENTION="$DEFAULT_BACKUP_RETENTION"
  fi

  if [[ "$DOPT" != "BO" ]]; then
    if [[ "$DOPT" == "BR" || ! -f "$VARS_FILE" ]]; then
      while true; do
        ans=$(whiptail --inputbox "Backup retention:\n\n• Enter 'ALL' to keep all backups (no pruning)\n• Or enter a number > 0 to keep only the newest N backups" 12 70 "$BACKUP_RETENTION" --title "Dispatcharr Options: Backup Retention" 3>&1 1>&2 2>&3) || {
          msg_warn "Retention dialog cancelled — keeping BACKUP_RETENTION=$BACKUP_RETENTION"
          break
        }
        if [[ "$ans" =~ ^[Aa][Ll][Ll]$ ]]; then
          BACKUP_RETENTION="ALL"; break
        elif [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -gt 0 ]; then
          BACKUP_RETENTION="$ans"; break
        else
          whiptail --msgbox "Invalid input. Type ALL or a positive number (e.g., 3)." 8 70 --title "Invalid Entry"
        fi
      done
      printf 'BACKUP_RETENTION=%s\n' "$BACKUP_RETENTION" > "$VARS_FILE"
      chmod 0644 "$VARS_FILE"
      msg_ok "Backup Retention is now set to $BACKUP_RETENTION."
    fi

    if [[ "$DOPT" == "BR" ]]; then
      exit 0
    fi

    if [[ "$DOPT" != "IV" ]]; then
      if ! check_for_gh_release "dispatcharr" "Dispatcharr/Dispatcharr"; then
        msg_ok "No new release available; current version is up to date."
        exit
      fi
      stop_spinner
    fi
  fi

  DISPATCH_USER="dispatcharr"
  DISPATCH_GROUP="dispatcharr"

  NGINX_HTTP_PORT="9191"
  WEBSOCKET_PORT="8001"
  GUNICORN_RUNTIME_DIR="dispatcharr"
  GUNICORN_SOCKET="/run/${GUNICORN_RUNTIME_DIR}/dispatcharr.sock"
  SYSTEMD_DIR="/etc/systemd/system"
  NGINX_SITE="/etc/nginx/sites-available/dispatcharr.conf"
  NGINX_SITE_ENABLED="${NGINX_SITE/sites-available/sites-enabled}"

  SERVER_IP="$(hostname -I | tr -s ' ' | cut -d' ' -f1)"

  DTHHMM="$(date +%F_%H-%M)"
  BACKUP_STEM=${APP,,}
  BACKUP_FILE="/root/${BACKUP_STEM}_${DTHHMM}.tar.gz"
  TMP_PGDUMP="/tmp/pgdump"
  DB_BACKUP_FILE="${TMP_PGDUMP}/${APP}_DB_${DTHHMM}.dump"
  BACKUP_GLOB="/root/${BACKUP_STEM}_*.tar.gz"

  if [ ! -z "$DOPT" ]; then
    msg_ok "Using DOPT=${DOPT}"
  fi

  if [[ "$DOPT" == "BO" ]]; then
    msg_ok "Build-Only enabled — skipping apt upgrade, backup/prune, and Django migrations."
  fi

  if [[ "$DOPT" != "BO" ]]; then
    if [[ "$BACKUP_RETENTION" =~ ^[0-9]+$ ]]; then
      EXISTING_BACKUPS=( $(ls -1 $BACKUP_GLOB 2>/dev/null | sort -r || true) )
      COUNT=${#EXISTING_BACKUPS[@]}
      if [ "$COUNT" -ge "$BACKUP_RETENTION" ]; then
        TO_REMOVE=$((COUNT - BACKUP_RETENTION + 1))
        LIST_PREVIEW=$(printf '%s\n' "${EXISTING_BACKUPS[@]}" | tail -n "$TO_REMOVE" | sed 's/^/  - /')
        MSG="Detected $COUNT existing backups in /root.
  A new backup will be created now, then $TO_REMOVE older backup(s) will be deleted
  to keep only the newest ${BACKUP_RETENTION}.

  Backups that would be removed:
  ${LIST_PREVIEW}

  Do you want to continue?"
        if ! whiptail --title "Dispatcharr Backup Warning" --yesno "$MSG" 20 78 --defaultno; then
          msg_warn "Backup/update cancelled by user at pre-flight backup limit check."
          exit 0
        fi
      fi
    fi
    if [ -d "$TMP_PGDUMP" ]; then
      shown=0
      for f in "$TMP_PGDUMP/${APP}_DB_"*.dump; do
        [ -e "$f" ] || continue
        if [ "$shown" -eq 0 ]; then
          msg_warn "Found leftover database dump(s) that may have been included in previous backups — removing:"
          shown=1
        fi
        echo "  - $(basename "$f")"
        sudo -u postgres rm -f "$f" 2>/dev/null || true
      done
    fi

    msg_info "Updating $APP LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated $APP LXC"
  fi

  msg_info "Stopping services for $APP"
  systemctl stop dispatcharr-celery
  systemctl stop dispatcharr-celerybeat
  systemctl stop dispatcharr-daphne
  systemctl stop dispatcharr
  msg_ok "Services stopped for $APP"

  if [[ "$DOPT" != "BO" ]]; then
    msg_ok "Backup Retention: ${BACKUP_RETENTION}"
    msg_info "Creating Backup of current installation"
    [ -d "$TMP_PGDUMP" ] || install -d -m 700 -o postgres -g postgres "$TMP_PGDUMP"
    sudo -u postgres pg_dump -Fc -f "${DB_BACKUP_FILE}" "$POSTGRES_DB"
    [ -s "${DB_BACKUP_FILE}" ] || { msg_error "Database dump is empty — aborting backup"; exit 1; }
    TAR_OPTS=( -C / --warning=no-file-changed --ignore-failed-read )
    TAR_EXCLUDES=(
      --exclude=opt/dispatcharr/env
      --exclude=opt/dispatcharr/env/**
      --exclude=opt/dispatcharr/frontend
      --exclude=opt/dispatcharr/frontend/**
      --exclude=opt/dispatcharr/static
      --exclude=opt/dispatcharr/static/**
    )
    TAR_ITEMS=(
      "${APP_DIR#/}"
      "${VERSION_FILE#/}"
      "${VARS_FILE#/}"
      "${CREDS_FILE#/}"
      "${NGINX_SITE#/}"
      "${NGINX_SITE_ENABLED#/}"
      "${SYSTEMD_DIR#/}/dispatcharr.service"
      "${SYSTEMD_DIR#/}/dispatcharr-celery.service"
      "${SYSTEMD_DIR#/}/dispatcharr-celerybeat.service"
      "${SYSTEMD_DIR#/}/dispatcharr-daphne.service"
      "${DB_BACKUP_FILE#/}"
    )
    $STD tar -czf "${BACKUP_FILE}" "${TAR_OPTS[@]}" "${TAR_EXCLUDES[@]}" "${TAR_ITEMS[@]}"
    rm -f "${DB_BACKUP_FILE}"
    if [[ "$BACKUP_RETENTION" =~ ^[0-9]+$ ]]; then
      ALL_BACKUPS="$(ls -1 $BACKUP_GLOB 2>/dev/null | sort -r || true)"
      COUNT="$(printf '%s\n' "$ALL_BACKUPS" | sed '/^$/d' | wc -l)"
      if [ "$COUNT" -gt "$BACKUP_RETENTION" ]; then
        TO_REMOVE=$((COUNT - BACKUP_RETENTION))
        OLD_BACKUPS="$(printf '%s\n' "$ALL_BACKUPS" | tail -n "$TO_REMOVE")"
        msg_warn "Found $COUNT existing backups — keeping newest $BACKUP_RETENTION and removing $TO_REMOVE older backup(s):"
        printf '%s\n' "$OLD_BACKUPS" | sed 's/^/  - /'
        printf '%s\n' "$OLD_BACKUPS" | xargs -r rm -f
      fi
    fi
    msg_ok "Backup Created: ${BACKUP_FILE}"

    if [[ "$DOPT" == "IV" ]]; then
      rm -f "$VERSION_FILE"
      msg_ok "Cleared version file"
    fi

    msg_info "Fetching latest Dispatcharr release"
    fetch_and_deploy_gh_release "dispatcharr" "Dispatcharr/Dispatcharr"
    $STD chown -R "$DISPATCH_USER:$DISPATCH_GROUP" "$APP_DIR"
    msg_ok "Release deployed"
  fi

  [[ -f "$VERSION_FILE" ]] && CURRENT_VERSION=$(<"$VERSION_FILE")

  msg_info "Ensuring runtime directories in APP_DIR"
  install -d -m 0755 -o "$DISPATCH_USER" -g "$DISPATCH_GROUP" \
    "${APP_DIR}/logo_cache" "${APP_DIR}/media"
  msg_ok "Runtime directories ensured"

  msg_info "Rebuilding frontend"
  sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}/frontend\"; rm -rf node_modules .cache dist build .next || true"
  sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}/frontend\"; if [ -f package-lock.json ]; then npm ci --silent --no-progress --no-audit --no-fund; else npm install --legacy-peer-deps --silent --no-progress --no-audit --no-fund; fi"
  $STD sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}/frontend\"; npm run build --loglevel=error -- --logLevel error"
  msg_ok "Frontend rebuilt"

  msg_info "Refreshing Python environment (uv)"
  export UV_INDEX_URL="https://pypi.org/simple"
  export UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cpu"
  export UV_INDEX_STRATEGY="unsafe-best-match"
  export PATH="/usr/local/bin:$PATH"
  $STD runuser -u "$DISPATCH_USER" -- bash -c 'cd "'"${APP_DIR}"'"; [ -x env/bin/python ] || uv venv --seed env || uv venv env'
  runuser -u "$DISPATCH_USER" -- env APP_DIR="$APP_DIR" bash -s <<'BASH'
  set -e
  cd "$APP_DIR"
  REQ=requirements.txt
  REQF=requirements.nouwsgi.txt
  if [ -f "$REQ" ]; then
    if grep -qiE '^\s*uwsgi(\b|[<>=~])' "$REQ"; then
      sed -E '/^\s*uwsgi(\b|[<>=~]).*/Id' "$REQ" > "$REQF"
    else
      cp "$REQ" "$REQF"
    fi
  fi
BASH
  runuser -u "$DISPATCH_USER" -- bash -c 'cd "'"${APP_DIR}"'"; . env/bin/activate; uv pip install -q -r requirements.nouwsgi.txt'
  runuser -u "$DISPATCH_USER" -- bash -c 'cd "'"${APP_DIR}"'"; . env/bin/activate; uv pip install -q gunicorn'
  ln -sf /usr/bin/ffmpeg "${APP_DIR}/env/bin/ffmpeg"
  msg_ok "Python environment refreshed"

  if [[ "$DOPT" != "BO" ]]; then
    msg_info "Running Django migrations"
    $STD sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}\"; source env/bin/activate; POSTGRES_DB='${POSTGRES_DB}' POSTGRES_USER='${POSTGRES_USER}' POSTGRES_PASSWORD='${POSTGRES_PASSWORD}' POSTGRES_HOST=localhost python manage.py migrate --noinput"
    msg_ok "Django migrations complete"
  fi

  msg_info "Collecting Django static files"
  $STD sudo -u "$DISPATCH_USER" bash -c "cd \"${APP_DIR}\"; source env/bin/activate; python manage.py collectstatic --noinput"
  msg_ok "Collecting Django static files complete"

  msg_info "Restarting services"
  $STD systemctl daemon-reload || true
  $STD systemctl restart dispatcharr dispatcharr-celery dispatcharr-celerybeat dispatcharr-daphne || true
  if [[ "$DOPT" != "BO" ]]; then
    $STD systemctl reload nginx 2>/dev/null || true
  fi
  msg_ok "Services restarted"

  msg_ok "Updated ${APP} to v${CURRENT_VERSION}"

  echo "Postgres (See $CREDS_FILE):"
  echo "    Database Name: $POSTGRES_DB"
  echo "    Database User: $POSTGRES_USER"
  echo "    Database Password: $POSTGRES_PASSWORD"
  echo

  echo "Nginx is listening on port ${NGINX_HTTP_PORT}."
  echo "Gunicorn socket: ${GUNICORN_SOCKET}."
  echo "WebSockets on port ${WEBSOCKET_PORT} (path /ws/)."
  echo
  echo "You can check logs via:"
  echo "  sudo journalctl -u dispatcharr -f"
  echo "  sudo journalctl -u dispatcharr-celery -f"
  echo "  sudo journalctl -u dispatcharr-celerybeat -f"
  echo "  sudo journalctl -u dispatcharr-daphne -f"
  echo
  echo "Visit the app at:"
  echo "  http://${SERVER_IP}:${NGINX_HTTP_PORT}"

  exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9191${CL}"
