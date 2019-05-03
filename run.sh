#!/bin/bash

CONFIG_DIR="${HOME}/config${RANDOM}"
CONFIG_FILE="$CONFIG_DIR/config"
set_auth() {
  local key_file="$CONFIG_DIR/api_key.pem"

  mkdir -p $CONFIG_DIR

  if [ -e "$CONFIG_FILE" ]; then
    warn 'OCI config file already exists in home directory and will be overwritten'
  fi

  #Write the key to a file
  echo "${WERCKER_OCI_OBJECTSTORE_API_KEY}" > $key_file
 
  echo '[DEFAULT]' > "$CONFIG_FILE"
  echo "user=${WERCKER_OCI_OBJECTSTORE_USER_OCID}" >> "$CONFIG_FILE"
  echo "tenancy=${WERCKER_OCI_OBJECTSTORE_TENANCY_OCID}" >> "$CONFIG_FILE"
  echo "fingerprint=${WERCKER_OCI_OBJECTSTORE_FINGERPRINT}" >> "$CONFIG_FILE"
  echo "region=${WERCKER_OCI_OBJECTSTORE_REGION}" >> "$CONFIG_FILE"
  echo "key_file=${key_file}" >> "$CONFIG_FILE"

  chmod 600 $key_file
  chmod 600 $CONFIG_FILE
  debug "generated OCI config file"
}

validate_oci_flags() {
  if [ -z "$WERCKER_OCI_OBJECTSTORE_TENANCY_OCID" ]; then
    fail 'missing or empty option tenancy_ocid, please check wercker.yml'
  fi

  if [ -z "$WERCKER_OCI_OBJECTSTORE_USER_OCID" ]; then
    fail 'missing or empty option user_ocid, please check wercker.yml'
  fi


  if [ -z "$WERCKER_OCI_OBJECTSTORE_FINGERPRINT" ]; then
    fail 'missing or empty option fingerprint, please check wercker.yml'
  fi

  if [ -z "$WERCKER_OCI_OBJECTSTORE_REGION" ]; then
    fail 'missing or empty option region, please check wercker.yml'
  fi

#TODO should we check for key? if it is a public bucket do they still need a key?
  if [ -z "$WERCKER_OCI_OBJECTSTORE_API_KEY" ]; then
    fail 'missing or empty option api_key, please check wercker.yml'
  fi

  if [ -z "$WERCKER_OCI_OBJECTSTORE_BUCKET_NAME" ]; then
    fail 'missing or empty option bucket_name, please check wercker.yml'
  fi

  if [ -z "$WERCKER_OCI_OBJECTSTORE_NAMESPACE" ]; then
    fail 'missing or empty option namespace, please check wercker.yml'
  fi
}

set_overwrite_flag_for_bulk() {
  if [ "$WERCKER_OCI_OBJECTSTORE_OVERWRITE" == "true" ] || [ "$WERCKER_OCI_OBJECTSTORE_OVERWRITE" == "TRUE" ]; then
    OVERWRITE_FLAG="--overwrite"
  else
    OVERWRITE_FLAG="--no-overwrite"
  fi
  WERCKER_OCI_OBJECTSTORE_OPTIONS="$WERCKER_OCI_OBJECTSTORE_OPTIONS $OVERWRITE_FLAG"
}

run_command() {
  set +e
  local cmd="$1"
  debug "$cmd"
  echo "running"

  $cmd
  if [ $? -ne 0 ];then
      fail "oci command $WERCKER_OCI_OBJECTSTORE_COMMAND failed";
  else
      success "completed command $WERCKER_OCI_OBJECTSTORE_COMMAND";
  fi
  set -e
}

bulk_upload_cmd() {
  set_overwrite_flag_for_bulk
  if [ -z "$WERCKER_OCI_OBJECTSTORE_LOCAL_DIR" ]; then
    fail 'missing or empty option local_dir, please check wercker.yml'
  fi

  if [ ! -d $WERCKER_OCI_OBJECTSTORE_LOCAL_DIR ] || [ -L $WERCKER_OCI_OBJECTSTORE_LOCAL_DIR ] ; then
    fail 'specified local directory does not exist or is not readable'
  fi

  if [ -z "$WERCKER_OCI_OBJECTSTORE_PREFIX" ]; then
    WERCKER_OCI_OBJECTSTORE_PREFIX="$(basename $WERCKER_OCI_OBJECTSTORE_LOCAL_DIR)/"
  fi

  local ocicmd="$WERCKER_STEP_ROOT/oci --config-file $CONFIG_FILE os object bulk-upload $WERCKER_OCI_OBJECTSTORE_OPTIONS --namespace $WERCKER_OCI_OBJECTSTORE_NAMESPACE --bucket-name $WERCKER_OCI_OBJECTSTORE_BUCKET_NAME --src-dir $WERCKER_OCI_OBJECTSTORE_LOCAL_DIR --object-prefix $WERCKER_OCI_OBJECTSTORE_PREFIX"
  run_command "$ocicmd"
}

bulk_download_cmd() {
  set_overwrite_flag_for_bulk
  if [ -z "$WERCKER_OCI_OBJECTSTORE_LOCAL_DIR" ]; then
    fail 'missing or empty option local_dir, please check wercker.yml'
  fi

  if [ ! -d $WERCKER_OCI_OBJECTSTORE_LOCAL_DIR ] || [ -L $WERCKER_OCI_OBJECTSTORE_LOCAL_DIR ] || [ ! -w $WERCKER_OCI_OBJECTSTORE_LOCAL_DIR ] ; then
    fail 'specified local directory does not exist or is not writable'
  fi

  if [ -n "$WERCKER_OCI_OBJECTSTORE_PREFIX" ]; then
    WERCKER_OCI_OBJECTSTORE_OPTIONS="$WERCKER_OCI_OBJECTSTORE_OPTIONS --prefix ""$WERCKER_OCI_OBJECTSTORE_PREFIX"""
  fi

  local ocicmd="$WERCKER_STEP_ROOT/oci --config-file $CONFIG_FILE os object bulk-download $WERCKER_OCI_OBJECTSTORE_OPTIONS -ns $WERCKER_OCI_OBJECTSTORE_NAMESPACE -bn $WERCKER_OCI_OBJECTSTORE_BUCKET_NAME --download-dir $WERCKER_OCI_OBJECTSTORE_LOCAL_DIR"
  run_command "$ocicmd"
}

single_file_upload_cmd() {
  #for the put operation there is no --overwrite - instead there is a --force flag. The --no-overwrite flag is supported.
  if [ "$WERCKER_OCI_OBJECTSTORE_OVERWRITE" == "true" ] || [ "$WERCKER_OCI_OBJECTSTORE_OVERWRITE" == "TRUE" ]; then
    OVERWRITE_FLAG="--force"
  else
    OVERWRITE_FLAG="--no-overwrite"
  fi
  WERCKER_OCI_OBJECTSTORE_OPTIONS="$WERCKER_OCI_OBJECTSTORE_OPTIONS $OVERWRITE_FLAG"

  if [ -z "$WERCKER_OCI_OBJECTSTORE_LOCAL_FILE" ]; then
    fail 'missing or empty option local_file is required for uploading a single file, please check wercker.yml'
  fi

  if [ ! -f $WERCKER_OCI_OBJECTSTORE_LOCAL_FILE ] || [ ! -r $WERCKER_OCI_OBJECTSTORE_LOCAL_FILE ] ; then
    fail 'specified local_file must be a regular file and must be readable'
  fi

  #default the object name to the same as the file's basename
  if [ -z "$WERCKER_OCI_OBJECTSTORE_OBJECT_NAME" ]; then
    WERCKER_OCI_OBJECTSTORE_OBJECT_NAME="$(basename $WERCKER_OCI_OBJECTSTORE_LOCAL_FILE)"
  fi

  local ocicmd="$WERCKER_STEP_ROOT/oci --config-file $CONFIG_FILE os object put $WERCKER_OCI_OBJECTSTORE_OPTIONS -ns $WERCKER_OCI_OBJECTSTORE_NAMESPACE -bn $WERCKER_OCI_OBJECTSTORE_BUCKET_NAME --name $WERCKER_OCI_OBJECTSTORE_OBJECT_NAME --file $WERCKER_OCI_OBJECTSTORE_LOCAL_FILE"
  run_command "$ocicmd"
}

single_file_download_cmd() {
  if [ -z "$WERCKER_OCI_OBJECTSTORE_OBJECT_NAME" ]; then
    fail 'missing or empty option object_name is required for downloading a single object, please check wercker.yml'
  fi

  #default the local file name to the same as the object name
  if [ -z "$WERCKER_OCI_OBJECTSTORE_LOCAL_FILE" ]; then
    WERCKER_OCI_OBJECTSTORE_LOCAL_FILE="$(basename $WERCKER_OCI_OBJECTSTORE_OBJECT_NAME)"
  fi

  local ocicmd="$WERCKER_STEP_ROOT/oci --config-file $CONFIG_FILE os object get $WERCKER_OCI_OBJECTSTORE_OPTIONS -ns $WERCKER_OCI_OBJECTSTORE_NAMESPACE -bn $WERCKER_OCI_OBJECTSTORE_BUCKET_NAME --name $WERCKER_OCI_OBJECTSTORE_OBJECT_NAME --file $WERCKER_OCI_OBJECTSTORE_LOCAL_FILE"
  run_command "$ocicmd"
}

oci_version_cmd() {
   local ocicmd="$WERCKER_STEP_ROOT/oci --config-file $CONFIG_FILE -version"
  run_command "$ocicmd" 
}

cleanup() {
  debug "Cleaning up before exit"
  if [ -d "$CONFIG_DIR" ]; then
    rm -rf $CONFIG_DIR
  fi
}

main() {
  trap "cleanup" EXIT
  validate_oci_flags
  
  set_auth

  #Python 3 has ascii as locale default which makes a library ("click") used by ocicli to fail.
  #Explicitly set locale to UTF-8
  export LANG=C.UTF-8
  export LC_ALL=C.UTF-8
  info "starting OCI object store synchronisation with oci version $($WERCKER_STEP_ROOT/oci --version)"

  case "$WERCKER_OCI_OBJECTSTORE_COMMAND" in
    bulk-upload)
        bulk_upload_cmd
        ;;
    bulk-download)
        bulk_download_cmd
        ;;
    put)
        single_file_upload_cmd
        ;;
    get)
        single_file_download_cmd
        ;;
    oci-version)
        oci_version_cmd
        ;;
#    start-db-node)
#        start_db_node_cmd
#        ;;
#    stop-db-node)
#        stop_db_node_cmd
#        ;;
    *)
        fail "unknown oci command $WERCKER_OCI_OBJECTSTORE_COMMAND - currently supported commands are [bulk-upload, bulk-download, get, put]"
        ;;
  esac
  cleanup
}

main