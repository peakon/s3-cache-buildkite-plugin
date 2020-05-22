#!/usr/bin/env bash

export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"save\":[{\"key\":\"v1-node-modules-{{ checksum \\\"package-lock.json\\\" }}\",\"paths\":[\"node_modules\", \"node_modules/.bin\"]},{\"key\":\"v1-eslint-cache-{{ .Environment.BUILDKITE_BRANCH }}\",\"paths\":[\"node_modules/.eslintcache\"],\"overwrite\":true}],\"restore\":[{\"keys\":[\"v1-node-modules-{{ checksum \\\"package-lock.json\\\" }}\"]},{\"keys\":[\"v1-eslint-cache-{{ .Environment.BUILDKITE_BRANCH }}\",\"v1-eslint-cache-master\"]}]}},{\"github.com/buildkite-plugins/docker-buildkite-plugin#v3.5.0\":{\"image\":\"peakon/node:13.8.0-ci\",\"environment\":[\"NPM_TOKEN\"],\"propagate-environment\":true}},{\"github.com/seek-oss/aws-sm-buildkite-plugin#v2.0.0\":{\"env\":{\"CODECOV_TOKEN\":\"buildkite/dashboard/codecov-token\"}}}]"

# returns a JSON object with plugin configuration 
function getPluginConfig {
  local config=$(echo $BUILDKITE_PLUGINS | jq '. | map(to_entries) | flatten | map(select(.key | match("peakon/s3-cache";"i"))) | .[0].value')
  if [[ "$config" == "null" ]]; then
      echo "peakon/s3-cache plugin is misconfigured"
      exit 1
  else 
    echo "$config"
  fi
}

# returns a JSON with restore config
function getRestoreConfig {
  local pluginConfig=$(getPluginConfig)
  echo $pluginConfig | jq '.restore'
}

# returns a JSON with save config
function getSaveConfig {
  local pluginConfig=$(getPluginConfig)
  echo $1 | jq '.save'
}

# $1 template string
function getCacheKey {
  local cache_key=$1
  while [[ "$cache_key" == *"{{"* ]]; do
    cache_key_prefix=$(echo "$cache_key" | sed -e 's/{.*//')
    template_value=$(echo "$cache_key" | sed -e 's/^[^\{{]*[^A-Za-z\.]*//' -e 's/.}}.*$//' | tr -d \' | tr -d \")

    local result=unsupported
    if [[ $template_value == *"checksum"* ]]; then
      checksum_argument=$(echo "$template_value" | sed -e 's/checksum*//')
      function=${template_value/"checksum"/"sha1sum"}
      result=$($function | awk '{print $1}')
    elif [[ $template_value == *".Environment.BUILDKITE_"* ]]; then
      local var_name=$(echo $template_value | sed -e 's/\.Environment\.//')
      result="${!var_name}"
    elif [[ $template_value == "epoch" ]]; then
      result=$(date +%s)
    fi
     cache_key=$(echo $cache_key | sed -e "s/[\{][\{]\([^}}]*\)[\}][\}]/$result/")
  done

  echo "$cache_key"
}

# $1 saveConfig
function getCacheItemsForSave {
  echo $1 | jq -r '.[] | "\(.key | @base64) \(.paths | join(" ") | @base64) \(.overwrite // "false") \(.when // "on_success")"'
}

# $1 restoreConfig
function getCacheItemsForRestore {
  echo $1 | jq -r '.[] | "\(.keys | [.[] | @base64] | join(" "))"'
}

# S3_PREFIX="${BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME}/${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}"

# $1 - cacheKey
# $2 - owerwrite (true/false)
# $2 - a string with space separated file paths
function s3Upload {
  echo "s3 upload called for $1"

  local s3_path="s3://${S3_PREFIX}/$1"
  local overwrite=$2
  local localPaths=($3)
  # TODO check if s3 key already exists before upload
  # tar --ignore-failed-read -cz ${localPaths[@]} | aws s3 cp - "$s3_path"
  # tar -cz ${localPaths[@]} | aws s3 cp - "$s3_path"
}

# $1 - cacheKey
function s3Restore {
  echo "s3 download called for $1"
  local s3_path="s3://${S3_PREFIX}/$1"
  set +e
  aws s3 cp "$s3_path" - | tar -xz
  if [ $? -ne 0 ]; then
    echo "false"
  else
    echo "true"
  fi
  set -e
}

function makeTempFile {
  tempFile=$(mktemp)
  cleanup() {
    rm $tempFile
  }
  trap cleanup EXIT
  echo "$tempFile"
}

function saveCache {
  local saveConfig=$(getSaveConfig)
  if [[ "$saveConfig" == "null" ]]; then 
      echo "No save config found, skipping"
      exit 0
  fi

  local tempFile=$(makeTempFile)
  getCacheItemsForSave "$saveConfig" > tempFile

  while read keyTemplateBase64 pathsBase64 overwrite when
  do
    keyTemplate=$(echo $keyTemplateBase64 | base64 -d)
    
    key=$(getCacheKey "$keyTemplate")
    paths=$(echo $pathsBase64 | base64 -d)
    
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
      s3Upload "$key" "$overwrite" "$paths"
    else
      echo "skipping upload"
    fi
  done < tempFile
}

function restoreCache {
  local restoreConfig=$(getRestoreConfig)
  if [[ "$restoreConfig" == "null" ]]; then 
      echo "No restore config found, skipping"
      exit 0
  fi
  
  local tempFile=$(makeTempFile)
  getCacheItemsForRestore "$restoreConfig" > tempFile

  while read cacheItemKeyTemplates
  do
    local cacheItemKeysTemplatesArray=($cacheItemKeyTemplates)
    for cacheItemKeyTemplate in "${cacheItemKeysTemplatesArray[@]}"
    do
      local cacheItemKeyTemplateDecoded=$(echo "$cacheItemKeyTemplate" | base64 -d)
      local cacheKey=$(getCacheKey "$cacheItemKeyTemplateDecoded")
      local isRestored=$(s3Restore "$cacheKey")
      if [[ "$isRestored" == "true" ]]; then
        echo "Successfully restored $cacheKey"
        break
      else
        echo "Failed to restore $cacheKey"
      fi
    done
  done < tempFile
}