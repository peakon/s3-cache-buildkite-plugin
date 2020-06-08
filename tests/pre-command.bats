#!/usr/bin/env bats

load "$BATS_PATH/load.bash"

tmp_dir=$(mktemp -d -t s3-cache-temp.XXXXXXXXXX)
pre_command_hook="$PWD/hooks/pre-command"

function cleanup {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

setup() {
  export BUILDKITE_BUILD_CHECKOUT_PATH=$tmp_dir
  export BUILDKITE_BUILD_ID=1
  export BUILDKITE_JOB_ID=0
  export BUILDKITE_ORGANIZATION_SLUG=my-org
  export BUILDKITE_PIPELINE_SLUG=my-pipeline
  export BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME=bucket
}

function teardown() {
    unstub aws
    unstub tar
}

@test "Pre-command succeeds to restore singe cache item" { 
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"v1-cache-key\"]}]}}]"

  stub aws \
    "s3 cp s3://${BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME}/${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}/v1-cache-key.tar.gz - : echo true"
  stub tar \
    "-xz : echo true"

  run "$pre_command_hook"

  assert_success
  assert_output --partial "Successfully restored v1-cache-key"
}

@test "Pre-command succeeds to restore from a fallback key if first key is missing" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"cache-key-missing\",\"cache-key-exists\"]}]}}]"
  
  stub aws \
    "s3 cp s3://${BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME}/${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}/cache-key-missing.tar.gz - : echo 'failed' && exit 1" \
    "s3 cp s3://${BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME}/${BUILDKITE_ORGANIZATION_SLUG}/${BUILDKITE_PIPELINE_SLUG}/cache-key-exists.tar.gz - : echo true"
  stub tar \
    "-xz : echo true" \
    "-xz : echo true"

  run "$pre_command_hook"

  assert_success
  assert_output --partial "Failed to restore cache-key-missing"
  assert_output --partial "Successfully restored cache-key-exists"
}
