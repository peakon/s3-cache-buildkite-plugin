#!/usr/bin/env bats

load "$BATS_PATH/load.bash"

tmp_dir=$(mktemp -d -t s3-cache-temp.XXXXXXXXXX)
post_command_hook="$PWD/hooks/post-command"

function cleanup {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

setup() {
  export BUILDKITE_BUILD_CHECKOUT_PATH=$tmp_dir
  export BUILDKITE_BUILD_ID=1
  export BUILDKITE_JOB_ID=0
  export BUILDKITE_PIPELINE_SLUG=my-pipeline
  export BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME=bucket
  export BUILDKITE_COMMAND_EXIT_STATUS=0
}

@test "Post-command succeeds" {
  export BUILDKITE_PLUGIN_S3_CACHE_SAVE_0_KEY=v1-node-modules
  run "$post_command_hook"
  assert_success
}
