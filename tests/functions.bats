#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

source "$PWD/lib/functions.bash"

setup() {
  bats_require_minimum_version 1.5.0
  export BUILDKITE_JOB_ID=job-id
  export BUILDKITE_BUILD_ID=1
  export BUILDKITE_ORGANIZATION_SLUG=my-org
  export BUILDKITE_PIPELINE_SLUG=my-pipeline
  export BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME=bucket
}

@test "getCacheKey without template strings" {
  run -0 getCacheKey "cache-key-1"
  assert_output "cache-key-1"
}

@test "getCacheKey with unknown template string" {
  run -0 getCacheKey "cache-key-1-{{ date }}"
  assert_output "cache-key-1-unsupported"
}

@test "getCacheKey with checksum of existing file" {
  run -0 getCacheKey "cache-key-1-{{ checksum "tests/data/testfile.txt" }}"
  assert_output "cache-key-1-147a61012231fd1a7bfe0c57c88a972e93817ace"
}

@test "getCacheKey with checksum of non-existing file" {
  run -0 getCacheKey "cache-key-1-{{ checksum "tests/data/missing.txt" }}"
  assert_output --partial "cache-key-1-"
}

@test "getCacheKey with appended checksums of multiple files" {
  run -0 getCacheKey "cache-key-1-{{ checksum "tests/data/testfile.txt" }}-{{ checksum "tests/data/testfile2.txt" }}"
  assert_output "cache-key-1-147a61012231fd1a7bfe0c57c88a972e93817ace-ddf8dc24aa1f00e7281d5d00699e43a5a6a8360b"
}

@test "getCacheKey with single checksum of aggregate contents of multiple files" {
  run -0 getCacheKey "cache-key-1-{{ checksum "tests/data/testfile.txt" "tests/data/testfile2.txt" }}"
  assert_output "cache-key-1-b6d04e8b6f0abf8144680c627db5ad59e589af75"
}

@test "getCacheKey with single checksum of aggregate contents of multiple files using glob pattern" {
  run -0 getCacheKey "cache-key-1-{{ checksum "tests/data/*.txt" }}"
  assert_output "cache-key-1-26cd40b759f311f23f7c791b21a494dc9ef76941"
}

@test "getCacheKey with BUILDKITE_* env var reference in template" {
  export BUILDKITE_FOO=bar
  run -0 getCacheKey "cache-key-1-{{ .Environment.BUILDKITE_FOO }}"
  unset BUILDKITE_FOO
  assert_output "cache-key-1-bar"
}

@test "getCacheKey with BUILDKITE_* env var that contains / in its value" {
  export BUILDKITE_FOO='foo/bar//buz'
  run -0 getCacheKey "cache-key-1-{{ .Environment.BUILDKITE_FOO }}"
  unset BUILDKITE_FOO
  assert_output "cache-key-1-foo_bar__buz"
}

@test "getCacheKey with BUILDKITE_* env var that contains & in its value" {
  export BUILDKITE_FOO='foo/bar&buz'
  run -0 getCacheKey "cache-key-1-{{ .Environment.BUILDKITE_FOO }}"
  unset BUILDKITE_FOO
  assert_output "cache-key-1-foo_bar_buz"
}

@test "getCacheKey with non-BUILDKITE_* env var reference in template" {
  export FOO=bar
  run -0 getCacheKey "cache-key-1-{{ .Environment.FOO }}"
  unset FOO
  assert_output "cache-key-1-unsupported"
}

@test "getCacheKey with no spacing inside {{}}" {
  export BUILDKITE_FOO=bar
  run -0 getCacheKey "cache-key-1-{{.Environment.BUILDKITE_FOO}}"
  unset BUILDKITE_FOO
  assert_output "cache-key-1-bar"
}

@test "getCacheKey with different spacing inside {{}}" {
  export BUILDKITE_FOO=bar
  run -0 getCacheKey "cache-key-1-{{ .Environment.BUILDKITE_FOO  }}"
  unset BUILDKITE_FOO
  assert_output "cache-key-1-bar"
}

@test "getCacheKey with epoch function in template" {
  run -0 getCacheKey "cache-key-1-{{ epoch }}"
  assert_regex "$output" ^cache-key-1-[0-9]{10}$
}

@test "getCacheKey only template" {
  run -0 getCacheKey "{{ epoch }}"
  assert_regex "$output" ^[0-9]{10}$
}

@test "restoreCache with single item" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"v1-cache-key\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=v1-cache-key

  function s3Restore { echo "true"; }
  export -f s3Restore
  
  run -0 restoreCache
  
  assert_output "Successfully restored v1-cache-key"
}

@test "restoreCache with multiple caches" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"cache-1-key\"]},{\"keys\":[\"cache-2-key-1\",\"cache-2-key-2\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=cache-1-key

  function s3Restore { echo "true"; }
  export -f s3Restore
  
  run -0 restoreCache
  
  assert_output --partial "Successfully restored cache-1-key"
  assert_output --partial "Successfully restored cache-2-key-1"
  refute_output --partial "cache-2-key-2"
}

@test "restoreCache with multiple caches and fallback to second cacheKey" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"cache-1-key\"]},{\"keys\":[\"cache-2-key-1\",\"cache-2-key-2\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=cache-1-key

  function s3Restore { 
    if [[ "$1" =~ ^cache-2-key-1$ ]]; then
      echo "false"
    else
      echo "true"
    fi
  }
  export -f s3Restore
  
  run -0 restoreCache
  
  assert_output --partial "Successfully restored cache-1-key"
  assert_output --partial "Failed to restore cache-2-key-1"
  assert_output --partial "Successfully restored cache-2-key-2"
}

@test "restoreCache for first plugin configuration in case of multiple plugins" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"cache-1-key\"]},{\"keys\":[\"cache-2-key-1\",\"cache-2-key-2\"]}]}},{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"cache-3-key\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=cache-1-key

  function s3Restore { 
    echo "true"
  }
  export -f s3Restore
  
  run -0 restoreCache
  
  assert_output --partial "Successfully restored cache-1-key"
  assert_output --partial "Successfully restored cache-2-key-1"
  refute_output --partial "Successfully restored cache-3-key"
}

@test "restoreCache for second plugin configuration in case of multiple plugins" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"cache-1-key\"]},{\"keys\":[\"cache-2-key-1\",\"cache-2-key-2\"]}]}},{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"cache-3-key\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=cache-3-key

  function s3Restore { 
    echo "true"
  }
  export -f s3Restore
  
  run -0 restoreCache
  
  refute_output --partial "Successfully restored cache-1-key"
  refute_output --partial "Successfully restored cache-2-key-1"
  assert_output --partial "Successfully restored cache-3-key"
}

@test "restoreCache with named cache should export CACHE_HIT=true" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"v1-cache-key\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=v1-cache-key
  export BUILDKITE_PLUGIN_S3_CACHE_ID="FOO_BAR"

  declare -a exportedEnvironment;

  function s3Restore { echo "true"; }
  function exportEnvVar {
    exportedEnvironment+="$1=$2"
  }
  export -f s3Restore
  export -f exportEnvVar
  
  restoreCache

  assert_equal "${exportedEnvironment[*]}" "BUILDKITE_PLUGIN_S3_CACHE_FOO_BAR_0_KEY_0_HIT=true"
}

@test "restoreCache with named cache should export CACHE_HIT=false" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"v1-cache-key\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=v1-cache-key
  export BUILDKITE_PLUGIN_S3_CACHE_ID="FOO_BAR"

  declare -a exportedEnvironment;

  function s3Restore { echo "false"; }
  function exportEnvVar {
    exportedEnvironment+="$1=$2"
  }
  export -f s3Restore
  export -f exportEnvVar
  
  restoreCache

  assert_equal "${exportedEnvironment[*]}" "BUILDKITE_PLUGIN_S3_CACHE_FOO_BAR_0_KEY_0_HIT=false"
}

@test "restoreCache with named cache should correctly export CACHE_HIT in case of cache miss on the first key" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"cache-1-key-1\", \"cache-1-key-2\"]},{\"keys\":[\"cache-2-key-1\"]} ]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=cache-1-key-1
  export BUILDKITE_PLUGIN_S3_CACHE_ID="FOO_BAR"

  declare -a exportedEnvironment;

  function s3Restore {
    if [[ "$1" == "cache-1-key-1" ]]; then
      echo "false"
    else
      echo "true"
    fi
  }
  function exportEnvVar {
    exportedEnvironment+="$1=$2"
  }
  export -f s3Restore
  export -f exportEnvVar
  
  restoreCache

  declare -a expected
  expected+="BUILDKITE_PLUGIN_S3_CACHE_FOO_BAR_0_KEY_0_HIT=false"
  expected+="BUILDKITE_PLUGIN_S3_CACHE_FOO_BAR_0_KEY_1_HIT=true"
  expected+="BUILDKITE_PLUGIN_S3_CACHE_FOO_BAR_1_KEY_0_HIT=true"

  assert_equal "${exportedEnvironment[*]}" "${expected[*]}"
}

@test "restoreCache with restore_dry_run=true should only check if cache exists on S3" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"v1-cache-key\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=v1-cache-key
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_DRY_RUN="true"

  function s3Exists { echo "true"; }
  export -f s3Exists
  
  run -0 restoreCache

  assert_output --partial "Successfully restored v1-cache-key"
}

@test "restoreCache with id:FOO_BAR and restore_dry_run=true should export BUILDKITE_PLUGIN_S3_CACHE_FOO_BAR_0_KEY_0_HIT=false if cache is missing" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"restore\":[{\"keys\":[\"v1-cache-key\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_0_KEYS_0=v1-cache-key
  export BUILDKITE_PLUGIN_S3_CACHE_RESTORE_DRY_RUN="true"
  export BUILDKITE_PLUGIN_S3_CACHE_ID="FOO_BAR"

  declare -a exportedEnvironment;

  function s3Exists { echo "false"; }
  function exportEnvVar {
    exportedEnvironment+="$1=$2"
  }
  export -f s3Exists
  export -f exportEnvVar
  
  restoreCache

  assert_equal "${exportedEnvironment[*]}" "BUILDKITE_PLUGIN_S3_CACHE_FOO_BAR_0_KEY_0_HIT=false"
}


@test "saveCache with single cacheItem" {
  export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"save\":[{\"key\":\"v1-node-modules\",\"paths\":[\"node_modules\"]}]}}]"
  export BUILDKITE_PLUGIN_S3_CACHE_SAVE_0_KEY=v1-node-modules
  function s3Exists {
    echo "false"
  }
  export -f s3Exists

  function s3Upload {
    echo "true"
  }
  export -f s3Upload
  
  run -0 saveCache
  
  assert_output --partial "Uploaded new cache for key: v1-node-modules"
}

# @test "saveCache with overwrite cacheItem" {
#   export BUILDKITE_PLUGINS="[{\"github.com/peakon/s3-cache-buildkite-plugin#v1.5.0\":{\"save\":[{\"key\":\"v1-node-modules\",\"paths\":[\"node_modules\"]},{\"key\":\"v1-eslint-cache\",\"paths\":[\"node_modules/.eslintcache\"],\"overwrite\":true}]}}]"

#   function s3Exists {
#     echo "false"
#   }
#   export -f s3Exists

#   function s3Upload {
#     echo "true"
#   }
#   export -f s3Upload
  
#   output=$(saveCache)
  
#   assert_success
#   assert_output --partial "Successfully saved v1-node-modules"
# }

# @test "saveCache with when=on_failure" {
#   echo true
# }

# @test "saveCache with when=always" {
#   echo true
# }

@test "s3ObjectKey without pipeline_name" {
  run -0 s3ObjectKey file
  assert_output "my-org/my-pipeline/file.tar.gz"
}

@test "s3ObjectKey with pipeline_name" {
  export BUILDKITE_PLUGIN_S3_CACHE_PIPELINE_NAME="another-pipeline"
  run -0 s3ObjectKey file
  assert_output "my-org/another-pipeline/file.tar.gz"
  unset BUILDKITE_PLUGIN_S3_CACHE_PIPELINE_NAME
}

@test "s3Upload with existing and non-existing paths" {
  makeTempFile() { echo /tmp/file.tar.gz; }
  export -f makeTempFile
  stub aws \
    "s3 cp /tmp/file.tar.gz s3://bucket/my-org/my-pipeline/s3_path.tar.gz --quiet : :"
  stub tar \
    "-czf /tmp/file.tar.gz local_paths : :" \
    "-czf /tmp/file.tar.gz local_paths : exit 1"

  run -0 s3Upload s3_path local_paths
  assert_output "true"
  run -0 s3Upload s3_path local_paths
  assert_output "false"

  unset makeTempFile
  unstub aws
  unstub tar
}
