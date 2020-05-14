/* eslint-disable no-console */
'use strict';

const AssetsCli = require('aws-sdk');
const stream = require('stream');
const util = require('util');
const pipeline = util.promisify(stream.pipeline);
const tar = require('tar');
const fs = require('fs');
const os = require('os');
const path = require('path');

class S3CacheAdapter {
  constructor({ bucket, keyPrefix, gzip = false }) {
    const s3ClientOptions =
      process.env.LOCALSTACK === 'true'
        ? {
            accessKeyId: 'dummy',
            secretAccessKey: 'dummy',
            endpoint: 'http://localhost:4566',
            s3ForcePathStyle: true,
          }
        : {};
    this.s3Client = new AssetsCli.S3(s3ClientOptions);
    this.bucket = bucket;
    this.keyPrefix = keyPrefix;
    this.gzip = gzip;
    this.tmpDir = os.tmpdir();
  }

  async restoreItem(key) {
    const getReadStream = (bucket, key) => {
      return this.s3Client
        .getObject({
          Bucket: bucket,
          Key: `${this.keyPrefix}/${key}.tar`,
        })
        .createReadStream();
    };

    await pipeline(getReadStream(this.bucket, key), tar.extract({ cwd: '.' }));
  }

  async saveItem(key, filePaths) {
    const upload = async (bucket, key, readable) => {
      const result = await this.s3Client
        .upload({
          Bucket: bucket,
          Key: `${this.keyPrefix}/${key}.tar`,
          Body: readable,
        })
        .promise();
      return result;
    };

    const tarFile = path.join(this.tmpDir, key);
    await tar.create(
      { gzip: this.gzip, file: tarFile },
      filePaths.filter(fs.existsSync)
    );
    await upload(this.bucket, key, fs.createReadStream(tarFile));
  }
}

module.exports = S3CacheAdapter;
