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
  constructor({ bucket, keyPrefix }) {
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
    this.tmpDir = os.tmpdir();
  }

  getFullKey(key) {
    return `${this.keyPrefix}/${key}.tar.gz`;
  }

  async restoreItem(key) {
    const getReadStream = (bucket, key) => {
      return this.s3Client
        .getObject({
          Bucket: bucket,
          Key: this.getFullKey(key),
        })
        .createReadStream();
    };

    await pipeline(getReadStream(this.bucket, key), tar.extract({ cwd: '.' }));
  }

  async saveItem(key, filePaths, { overwrite } = { overwrite: false }) {
    const objectExists = async (bucket, key) => {
      try {
        await this.s3Client.headObject({ Bucket: bucket, Key: key }).promise();
        return true;
      } catch (e) {
        return false;
      }
    };

    const upload = async (bucket, key, readable) => {
      await this.s3Client
        .upload({
          Bucket: bucket,
          Key: key,
          Body: readable,
        })
        .promise();
    };

    const s3ObjectKey = this.getFullKey(key);
    if (await objectExists(this.bucket, s3ObjectKey)) {
      if (overwrite) {
        console.log(`[s3-cache-adapter] Overwriting ${key}`);
      } else {
        return;
      }
    }
    const tarFile = path.join(this.tmpDir, key);
    await tar.create(
      { gzip: true, file: tarFile },
      filePaths.filter(fs.existsSync)
    );
    await upload(this.bucket, s3ObjectKey, fs.createReadStream(tarFile));
  }
}

module.exports = S3CacheAdapter;
