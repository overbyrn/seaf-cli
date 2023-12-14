#!/bin/bash

#Debug
#set -x

CONFIG_DIR="${CONFIG_DIR:-/app/.ccnet}"
SYNC_ROOT="${SYNC_ROOT:-/app/seafile}"
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"
SEAFILE_UID="${SEAFILE_UID:-1000}"
SEAFILE_GID="${SEAFILE_GID:-1000}"
SEAFILE_UMASK="${SEAFILE_UMASK:-022}"
CONNECT_RETRIES="${CONNECT_RETRIES:-5}"
DISABLE_VERIFY_CERTIFICATE="${DISABLE_VERIFY_CERTIFICATE:-true}"

function log() {
  local time=$(date +"%F %T")
  echo "$time $1 "
  echo "[$time] $1 " &>> /app/start.log
}

function cleanup() {
  kill -s SIGTERM $!
  exit 0
}

get () {
  NAME="$1"
  JSON="$2"
  # Tries to regex setting name from config. Only works with strings for now
  echo $JSON | grep -Po '"'"$NAME"'"\s*:\s*.*?[^\\]"+,*' | sed -n -e 's/.*: *"\(.*\)",*/\1/p'
}

setup_uid() {
  # Setup umask
  umask "${SEAFILE_UMASK}"
  # Setup user id
  if [ ! "$(id -u seafile)" -eq "${SEAFILE_UID}" ]; then
      # Change the SEAFILE_UID
      usermod -o -u "${SEAFILE_UID}" seafile
  fi
  # Setup group id
  if [ ! "$(id -g seafile)" -eq "${SEAFILE_GID}" ]; then
      # Change the SEAFILE_UID
      groupmod -o -g "${SEAFILE_GID}" seafile
  fi
  id seafile
  log "UID='${SEAFILE_UID}' GID='${SEAFILE_GID}'"
}

start_seafile() {
  retries="${CONNECT_RETRIES}"
  count=0
  runuser -l seafile -c "seaf-cli start -c ${CONFIG_DIR}"
  sleep 3
  while :
  do
    runuser -l seafile -c "seaf-cli status -c ${CONFIG_DIR}"
    exit=$?
    wait=$((2 ** $count))
    count=$(($count + 1))
    if [ $exit -eq 0 ]; then
      runuser -l seafile -c "seaf-cli config -c ${CONFIG_DIR} -k disable_verify_certificate -v $DISABLE_VERIFY_CERTIFICATE"
      return 0
    fi
    if [ $count -lt $retries ]; then
      echo "Retry $count/$retries exited $exit, retrying in $wait seconds..."
      sleep $wait
    else
      echo "Retry $count/$retries exited $exit, no more retries left."
      return $exit
    fi
  done
}

setup_lib_sync() {
    if [ ! -d $SYNC_ROOT ]; then
      log "Using new data directory: $SYNC_ROOT"
      mkdir -p $SYNC_ROOT
      chown seafile:seafile -R $SYNC_ROOT
    fi
    TOKEN_JSON=$(curl -d "username=$USERNAME" -d "password=$PASSWORD" ${SERVER_URL}:${SERVER_PORT}/api2/auth-token/ 2> /dev/null)
    TOKEN=$(get token "$TOKEN_JSON")
    if [ "$TOKEN" == "" ]; then
      log "Unable to get token. Check your user credentials, server url and server port."
      return
    fi
    LIBS_IN_SYNC=$(runuser -l seafile -c "seaf-cli list -c ${CONFIG_DIR}")
    LIBS=(${LIBRARY_ID//:/ })
    for i in "${!LIBS[@]}"
    do
      # TO DO: validate library id exists
	  LIB="${LIBS[i]}"
      LIB_JSON=$(curl -G -H "Authorization: Token $TOKEN" -H 'Accept: application/json; indent=4' ${SERVER_URL}:${SERVER_PORT}/api2/repos/${LIB}/ 2> /dev/null)
      LIB_NAME=$(get name "$LIB_JSON")
      LIB_NAME_NO_SPACE=$(echo $LIB_NAME|sed 's/[ \(\)]/_/g')
      LIB_DIR=${SYNC_ROOT}/${LIB_NAME_NO_SPACE}
      LIB_IN_SYNC=$(echo "$LIBS_IN_SYNC" | grep "$LIB")
      if [ ${#LIB_IN_SYNC} -eq 0 ]; then
        if [ ! -d "${LIB_DIR}" ]; then
          log "Creating library directory: ${LIB_DIR}"
          mkdir -p "${LIB_DIR}"
          chown seafile:seafile -R "${LIB_DIR}"
        fi        
		log "Syncing $LIB_NAME"
        runuser -l seafile -c "seaf-cli sync -c ${CONFIG_DIR} -l \"\"$LIB\"\" -d \"$LIB_DIR\" -s \"${SERVER_URL}:${SERVER_PORT}\" -u \"$USERNAME\" -p \"$PASSWORD\""
      fi
    done	
}

keep_in_foreground() {
  trap cleanup SIGINT SIGTERM

  while [ 1 ]; do
    sleep $SYNC_INTERVAL &
	date +"%Y-%m-%d %H:%M:%S"
    runuser -l seafile -c "seaf-cli status -c ${CONFIG_DIR}"
    wait $!
  done
}

### MAIN ###
log "calling setup_uid"
setup_uid

log "calling start_seafile"
start_seafile

log "calling setup_lib_sync"
setup_lib_sync

log "calling keep_in_foreground"
keep_in_foreground

