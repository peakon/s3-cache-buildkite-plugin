#!/usr/bin/env bats

load '/usr/local/lib/bats/load.bash'

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
  export BUILDKITE_PIPELINE_SLUG=my-pipeline
  export BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME=bucket
}

@test "Pre-command succeeds" {
  cd "$BUILDKITE_BUILD_CHECKOUT_PATH"

  stub docker "build"
  
  stub docker \
    "run --label com.buildkite.job-id=${BUILDKITE_JOB_ID} --workdir=/workdir --volume=${BUILDKITE_BUILD_CHECKOUT_PATH}:/workdir -it --rm -e BUILDKITE_BUILD_ID -e BUILDKITE_JOB_ID -e BUILDKITE_PLUGINS -e BUILDKITE_PIPELINE_SLUG -e HTTP_PROXY -e HTTPS_PROXY s3-cache-buildkite-plugin:$BUILDKITE_JOB_ID --action=restore --bucket bucket"

  run "$pre_command_hook"

  assert_success
}