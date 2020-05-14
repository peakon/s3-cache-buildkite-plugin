/* eslint-disable no-console */
'use strict';

const { toCacheKey } = require('./template');
const fs = require('fs-extra');

class CacheLoader {
  constructor(cacheAdapter) {
    this.cacheAdapter = cacheAdapter;
  }

  async restore(cacheItems) {
    for (const cacheItem of cacheItems) {
      for (let i = 0; i < cacheItem.keys.length; i++) {
        const cacheKey = await toCacheKey(cacheItem.keys[i]);
        try {
          console.log(`[cache-loader] restoring ${cacheKey}`);
          await this.cacheAdapter.restoreItem(cacheKey);
          console.log('[cache-loader] restored');
          break;
        } catch (e) {
          console.log(`[cache-loader] restore failed (${e.message})`);
          continue;
        }
      }
    }
  }

  /**
   *
   * @param {Array} cacheItems Array of Objects: { key: 'foo', paths:['bar']}
   */
  async save(cacheItems, { buildPassed = true } = { buildPassed: true }) {
    for (const cacheItem of cacheItems) {
      const when = cacheItem.when || 'on_success';
      const cacheKey = await toCacheKey(cacheItem.key);
      if (
        (!buildPassed && when === 'on_failure') ||
        (buildPassed && when === 'on_success') ||
        when === 'always'
      ) {
        console.log(
          `[cache-loader] saving ${cacheKey} <= ${JSON.stringify(
            cacheItem.paths
          )}`
        );
        const invalidPaths = cacheItem.paths.filter((p) => !fs.existsSync(p));
        if (invalidPaths.length) {
          console.log(
            `[cache-loader] ignoring missing paths ${JSON.stringify(
              invalidPaths
            )}`
          );
        }
        await this.cacheAdapter.saveItem(cacheKey, cacheItem.paths, {
          overwrite: !!cacheItem.overwrite,
        });
        console.log(`[cache-loader] saved ${cacheKey}`);
      } else {
        console.log(
          `[cache-loader] skipping saving ${cacheKey}. Command status doesn't satisfy "when=${when}" condition)`
        );
      }
    }
  }
}

module.exports = CacheLoader;
