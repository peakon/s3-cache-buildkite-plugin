#!/usr/bin/env bash

if [[ -n "${BUILDKITE_PLUGIN_S3_CACHE_AWS_PROFILE:-}" ]]; then
  aws_cli_args=(--profile "$BUILDKITE_PLUGIN_S3_CACHE_AWS_PROFILE")
else
  aws_cli_args=()
fi

# returns a JSON object with plugin configuration 
function getPluginConfig {
  local config
  config=$(echo "$BUILDKITE_PLUGINS" | jq '. | map(to_entries) | flatten | map(select(.key | match("peakon/s3-cache";"i"))) | map(.value)')
  if [[ "$config" == "null" ]]; then
      echo "peakon/s3-cache plugin is misconfigured"
      exit 1
  else 
    echo "$config"
  fi
}

# returns a JSON with restore config
function getRestoreConfig {
  local pluginConfig
  pluginConfig=$(getPluginConfig)
  echo "$pluginConfig" | jq --arg key0 "${BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0:-}" 'map(select((.restore[0].keys[0] == $key0) and (.restore[0].keys[0] | length > 0))) | map(.restore) | flatten'
}

# returns a JSON with save config
function getSaveConfig {
  local pluginConfig
  pluginConfig=$(getPluginConfig)
  echo "$pluginConfig" | jq --arg key0 "${BUILDKITE_PLUGIN_S3_CACHE_SAVE_0_KEY:-}" 'map(select((.save[0].key == $key0) and (.save[0].key | length > 0))) | map(.save) | flatten'
}

# $1 template string
function getCacheKey {
  local cache_key
  cache_key="$1"
  while [[ "$cache_key" == *"{{"* ]]; do
    template_value=$(echo "$cache_key" | sed -e 's/^[^\{{]*[^A-Za-z\.]*//' -e 's/\s*}}.*$//' | tr -d \' | tr -d \")
    local result
    result=unsupported
    if [[ $template_value == *"checksum"* ]]; then
      function=${template_value/"checksum"/"sha1sum"}
      result=$($function | awk '{print $1}')
    elif [[ $template_value == *".Environment.BUILDKITE_"* ]]; then
      local var_name
      var_name="${template_value//\.Environment\./}"
      var_value="${!var_name}"
      result=${var_value//[^a-zA-Z0-9]/_}
    elif [[ "$template_value" == "epoch" ]]; then
      result=$(date +%s)
    fi
    # shellcheck disable=SC2001
    cache_key=$(echo "$cache_key" | sed -e "s/[\{][\{]\([^}}]*\)[\}][\}]/$result/")
  done

  echo "$cache_key"
}

# $1 saveConfig
function getCacheItemsForSave {
  echo "$1" | jq -r '.[] | "\(.key | @base64) \(.paths | join(" ") | @base64) \(.overwrite // "false") \(.when // "on_success")"'
}

# $1 restoreConfig
function getCacheItemsForRestore {
  echo "$1" | jq -r '.[] | "\(.keys | [.[] | @base64] | join(" "))"'
}

function s3ObjectKey {
  echo "${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}/${1}.tar.gz"
}

function s3Path {
  local s3Key
  s3Key=$(s3ObjectKey "$1")
  echo "s3://${BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME}/${s3Key}"
}

# $1 - cacheKey
function s3Exists {
  local s3Key
  s3Key=$(s3ObjectKey "$1")
  local s3KeyExists="true"
  aws "${aws_cli_args[@]}" s3api head-object --bucket "$BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME" --key "$s3Key" &>/dev/null || s3KeyExists=false
  echo "$s3KeyExists"
}

# $1 - cacheKey
# $2 - a string with space separated file paths
function s3Upload {
  local s3_path
  local localPaths
  s3_path=$(s3Path "$1")
  localPaths=("$2")
  set +e
  # shellcheck disable=SC2068
  if ! (tar --ignore-failed-read -cz ${localPaths[@]} | aws "${aws_cli_args[@]}" s3 cp - "$s3_path"); then
    echo "false"
  else
    echo "true"
  fi
  set -e
}

# $1 - cacheKey
function s3Restore {
  local s3_path
  s3_path=$(s3Path "$1")
  set +e
  if ! aws "${aws_cli_args[@]}" s3 cp "$s3_path" - | tar -xz > /dev/null; then
    echo "false"
  else
    echo "true"
  fi
  set -e
}

function makeTempFile {
  tempFile=$(mktemp)
  cleanup() {
    rm "$tempFile"
  }
  trap cleanup EXIT
  echo "$tempFile"
}

function saveCache {
  local saveConfig
  saveConfig=$(getSaveConfig)
  if [[ "$saveConfig" == "[]" ]]; then
      echo "No save config found, skipping"
      return
  fi

  local tempFile
  tempFile=$(makeTempFile)
  getCacheItemsForSave "$saveConfig" > "$tempFile"

  while read -r keyTemplateBase64 pathsBase64 overwrite when
  do
    keyTemplate=$(echo "$keyTemplateBase64" | base64 -d)
    
    key=$(getCacheKey "$keyTemplate")
    paths=$(echo "$pathsBase64" | base64 -d)
    
    if [[ ! "$when" =~ ^(on_success|on_failure|always)$ ]]; then
      echo ":warn: invalid value specified for 'when' option ($when), ignoring"
      when="on_success"
    fi
    if [[ ! "$overwrite" =~ ^(true|false)$ ]]; then
      echo ":warn: invalid value specified for 'overwrite' option ($overwrite), ignoring"
      overwrite="false"
    fi

    if [[ "${BUILDKITE_COMMAND_EXIT_STATUS}" -ne 0 ]]; then
      uploadConditions="^(on_failure|always)$"
    else
      uploadConditions="^(on_success|always)$"
    fi
    
    if [[ "$when" =~ $uploadConditions ]]; then
      local alreadyOnS3
      alreadyOnS3=$(s3Exists "$key")
      if [[ "$alreadyOnS3" == "false" ]]; then
        echo "Uploading new cache for key: $key"
      elif [[ "$overwrite" == "true" ]]; then
        echo "Overwriting existing cache for key: $key"
      else 
        echo "Cache already exists (and will not be updated) for key: $key"
        continue
      fi
      local isSaved
      isSaved=$(s3Upload "$key" "$paths")
      if [[ "$isSaved" == "true" ]]; then
        echo "Uploaded new cache for key: $key"
      else
        echo "Failed to upload new cache for key: $key"
      fi
    else
      echo "Skipping cache upload for key: $key ('when' condition is not met)"
    fi
  done < "$tempFile"
}

function restoreCache {
  local restoreConfig
  restoreConfig=$(getRestoreConfig)
  if [[ "$restoreConfig" == "[]" ]]; then
      echo "No restore config found, skipping"
      return
  fi
  
  local tempFile
  tempFile=$(makeTempFile)
  getCacheItemsForRestore "$restoreConfig" > "$tempFile"

  while read -r cacheItemKeyTemplates
  do
    # shellcheck disable=SC2206
    local cacheItemKeysTemplatesArray=($cacheItemKeyTemplates)
    for cacheItemKeyTemplate in "${cacheItemKeysTemplatesArray[@]}"
    do
      local cacheItemKeyTemplateDecoded
      local isRestored
      local cacheKey
      cacheItemKeyTemplateDecoded=$(echo "$cacheItemKeyTemplate" | base64 -d)
      cacheKey=$(getCacheKey "$cacheItemKeyTemplateDecoded")
      isRestored=$(s3Restore "$cacheKey")
      if [[ "$isRestored" == "true" ]]; then
        echo "Successfully restored $cacheKey"
        break
      else
        echo "Failed to restore $cacheKey. The following error occured: ${isRestored}"
      fi
    done
  done < "$tempFile"
}
