# S3 Cache Buildkite Plugin

![CI](https://github.com/peakon/s3-cache-buildkite-plugin/workflows/CI/badge.svg?branch=master)

Save and restore cache to and from AWS S3.

## Example

Add the following to your `pipeline.yml`:

```yml
steps:
  - command: npm install && npm test
    plugins:
      - peakon/s3-cache#v2.0.0:
          save:
            - key: 'v1-node-modules-{{ checksum("package-lock.json") }}' # required
              paths: [ "node_modules" ] # required, array of strings
              when: on_success # optional, one of {always, on_success, on_failure}, default: on_success
              overwrite: false # optional, set true to overwrite cache on S3 even if object already exists
          restore:
            - keys:
                - 'v1-node-modules-{{ checksum "package-lock.json" }}'
                - 'v1-node-modules-' # will load latest cache starting with v1-node-modules- (not yet implemented)
```

## Configuration


### Prerequisites

Make sure to set `BUILDKITE_PLUGIN_S3_CACHE_BUCKET_NAME=your-cache-bucket-name` before using this plugin.

### Plugin

You can specify either `save` or `restore` or both of them for a single pipeline step.

#### `save` properties


#### `restore` properties


#### Supported functions

- `checksum 'filename'` - sha256 hash of a `filename`

- `epoch` - time in seconds since Unix epoch (in UTC)

- `.Environment.SOME_VAR` - a value of environment variable `SOME_VAR`


#### AWS profiles

You can specify a custom AWS profile to be used by AWS CLI

- in pipeline YAML (`aws_profile: profile_name`)
- via `BUILDKITE_PLUGIN_S3_CACHE_AWS_PROFILE` environment variable (e.g. inside agent environment hook).

## Developing

To run the tests:

```shell
docker-compose run --rm tests
```

## Contributing

1. Fork the repo
2. Make the changes
3. Run the tests
4. Commit and push your changes
5. Send a pull request
