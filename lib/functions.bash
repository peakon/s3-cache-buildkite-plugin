#!/usr/bin/env bash

# export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"save\":[{\"key\":\"v1-node-modules-{{ checksum \\\"package-lock.json\\\" }}\",\"paths\":[\"node_modules\", \"node_modules/.bin\"]},{\"key\":\"v1-eslint-cache-{{ .Environment.BUILDKITE_BRANCH }}\",\"paths\":[\"node_modules/.eslintcache\"],\"overwrite\":true}],\"restore\":[{\"keys\":[\"v1-node-modules-{{ checksum \\\"package-lock.json\\\" }}\"]},{\"keys\":[\"v1-eslint-cache-{{ .Environment.BUILDKITE_BRANCH }}\",\"v1-eslint-cache-master\"]}]}},{\"github.com/buildkite-plugins/docker-buildkite-plugin#v3.5.0\":{\"image\":\"peakon/node:13.8.0-ci\",\"environment\":[\"NPM_TOKEN\"],\"propagate-environment\":true}},{\"github.com/seek-oss/aws-sm-buildkite-plugin#v2.0.0\":{\"env\":{\"CODECOV_TOKEN\":\"buildkite/dashboard/codecov-token\"}}}]"
# export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"v1-node-modules-{{ checksum \\\"package-lock.json\\\" }}\"]},{\"keys\":[\"v1-eslint-cache-{{ .Environment.BUILDKITE_BRANCH }}\",\"v1-eslint-cache-master\"]}]}}]"

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
  echo $pluginConfig | jq '.save'
}

# $1 template string
function getCacheKey {
  local cache_key=$1
  while [[ "$cache_key" == *"{{"* ]]; do
    cache_key_prefix=$(echo "$cache_key" | sed -e 's/{.*//')
    template_value=$(echo "$cache_key" | sed -e 's/^[^\{{]*[^A-Za-z\.]*//' -e 's/\s*}}.*$//' | tr -d \' | tr -d \")

    # echo $template_value

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

function s3ObjectKey {
  echo "${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}/${1}.tar.gz"
}

function s3Path {
  local s3Key=$(s3ObjectKey "$1")
  echo "s3://${BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME}/${s3Key}"
}

# $1 - cacheKey
function s3Exists {
  local s3Key=$(s3ObjectKey "$1")
  aws s3api head-object --bucket "$BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME" --key $s3Key || not_exist=true
  if [ $not_exist ]; then
    echo "false"
  else
    echo "true"
  fi
}

# $1 - cacheKey
# $2 - a string with space separated file paths
function s3Upload {
  local s3_path=$(s3Path "$1")
  local localPaths=($2)
  set +e
  tar --ignore-failed-read -cz ${localPaths[@]} | aws s3 cp - "$s3_path"
  if [ $? -ne 0 ]; then
    echo "false"
  else
    echo "true"
  fi
  set -e
}

# $1 - cacheKey
function s3Restore {
  local s3_path=$(s3Path "$1")
  set +e
  output=$(aws s3 cp "$s3_path" - | tar -xz)
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
      return
  fi

  local tempFile=$(makeTempFile)
  getCacheItemsForSave "$saveConfig" > $tempFile

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
      local alreadyOnS3=$(s3Exists "$key")
      if [[ "$alreadyOnS3" == "false" ]]; then
        echo "Uploading new cache for key: $key"
      elif [[ "$overwrite" == "true" ]]; then
        echo "Overwriting existing cache for key: $key"
      else 
        echo "Cache already exists (and will not be updated) for key: $key"
      fi
      local isSaved=$(s3Upload "$key" "$paths")
      if [[ "$isSaved" == "true" ]]; then
        echo "Uploaded new cache for key: $key"
      else
        echo "Failed to upload new cache for key: $ke"
      fi
    else
      echo "Skipping cache upload for key: $key ('when' condition is not met)"
    fi
  done < $tempFile
}

function restoreCache {
  local restoreConfig=$(getRestoreConfig)
  if [[ "$restoreConfig" == "null" ]]; then 
      echo "No restore config found, skipping"
      return
  fi
  
  local tempFile=$(makeTempFile)
  getCacheItemsForRestore "$restoreConfig" > $tempFile

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
  done < $tempFile
}