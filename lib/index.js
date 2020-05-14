/* eslint-disable no-console */
'use strict';

const CacheLoader = require('./cache-loader');
const S3CacheAdapter = require('./s3-cache-adapter');
const meow = require('meow');

const cli = meow(
  `
    Usage
      $ node lib --bucket=bucketname --action=save|restore --keyPrefix=$pipelineName --stepExitCode=exitCode
  `,
  {
    description: false,
    flags: {
      bucket: {
        type: 'string',
        isRequred: true,
      },
      action: {
        type: 'string',
        isRequred: true,
      },
      keyPrefix: {
        type: 'string',
        isRequired: true,
      },
      gzip: {
        type: 'boolean',
        default: false,
      },
      stepExitCode: {
        type: 'number',
        default: 0,
      },
    },
  }
);

(async () => {
  let pluginsConfig;
  try {
    pluginsConfig = JSON.parse(process.env.BUILDKITE_PLUGINS);
  } catch (e) {
    console.error('Error: BUILDKITE_PLUGINS env var is not set');
    process.exit(1);
  }

  const s3CachePlugin = pluginsConfig.find((config) =>
    Object.keys(config)[0].startsWith(
      'github.com/peakon/s3-cache-buildkite-plugin'
    )
  );

  if (s3CachePlugin) {
    const configuration = Object.entries(s3CachePlugin)[0][1];

    const { action, bucket, keyPrefix, gzip, stepExitCode } = cli.flags;

    if (!['save', 'restore'].includes(action)) {
      throw new Error('Invalid flags. Use --help to see available options.');
    }

    const cacheLoader = new CacheLoader(
      new S3CacheAdapter({ bucket, keyPrefix, gzip })
    );
    await cacheLoader[action].apply(cacheLoader, [
      configuration[action],
      {
        buildPassed: stepExitCode === 0,
      },
    ]);
  }
})();
