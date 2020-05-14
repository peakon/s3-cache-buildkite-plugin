'use strict';

const CacheLoader = require('./cache-loader');

const adapter = {
  restoreItem: jest.fn(),
  saveItem: jest.fn(),
};

const loader = new CacheLoader(adapter);

describe('CacheLoader', () => {
  beforeEach(() => {
    jest.resetAllMocks();
  });

  describe('save', () => {
    describe('when build has not failed', () => {
      it('saves cache', async () => {
        await loader.save([{ key: 'key', paths: ['path'] }]);
        expect(adapter.saveItem).toHaveBeenCalledWith('key', ['path']);
      });

      it('saves multiple caches', async () => {
        await loader.save([
          { key: 'key', paths: ['path'] },
          { key: 'key2', paths: ['path'] },
        ]);
        expect(adapter.saveItem).toHaveBeenCalledWith('key', ['path']);
        expect(adapter.saveItem).toHaveBeenCalledWith('key2', ['path']);
      });

      it('saves cache that has when: on_success', async () => {
        await loader.save([
          { key: 'key', paths: ['path'], when: 'on_success' },
        ]);
        expect(adapter.saveItem).toHaveBeenCalledWith('key', ['path']);
      });

      it('does not save cache that has when: on_failure', async () => {
        await loader.save([
          { key: 'key', paths: ['path'], when: 'on_failure' },
        ]);
        expect(adapter.saveItem).not.toHaveBeenCalledWith('key', ['path']);
      });

      it('saves cache that has when: always', async () => {
        await loader.save([{ key: 'key', paths: ['path'], when: 'always' }]);
        expect(adapter.saveItem).toHaveBeenCalledWith('key', ['path']);
      });
    });

    describe('when build has failed', () => {
      it('does not save cache', async () => {
        await loader.save([{ key: 'key', paths: ['path'] }], {
          buildPassed: false,
        });
        expect(adapter.saveItem).not.toHaveBeenCalledWith('key', ['path']);
      });

      it('does not save cache that has when: on_success', async () => {
        await loader.save(
          [{ key: 'key', paths: ['path'], when: 'on_success' }],
          { buildPassed: false }
        );
        expect(adapter.saveItem).not.toHaveBeenCalledWith('key', ['path']);
      });

      it('saves cache that has when: always', async () => {
        await loader.save([{ key: 'key', paths: ['path'], when: 'always' }], {
          buildPassed: false,
        });
        expect(adapter.saveItem).toHaveBeenCalledWith('key', ['path']);
      });

      it('saves cache that has when: on_failure', async () => {
        await loader.save(
          [{ key: 'key', paths: ['path'], when: 'on_failure' }],
          { buildPassed: false }
        );
        expect(adapter.saveItem).toHaveBeenCalledWith('key', ['path']);
      });
    });
  });

  describe('restore', () => {
    it('restores cache', async () => {
      await loader.restore([{ keys: ['key'] }]);
      expect(adapter.restoreItem).toHaveBeenCalledWith('key');
    });

    it('restores multiple caches', async () => {
      await loader.restore([{ keys: ['key'] }, { keys: ['key2'] }]);
      expect(adapter.restoreItem).toHaveBeenCalledWith('key');
      expect(adapter.restoreItem).toHaveBeenCalledWith('key2');
    });

    it('restores first found key if multiple keys specified', async () => {
      await loader.restore([{ keys: ['key', 'key2'] }]);
      expect(adapter.restoreItem).toHaveBeenCalledWith('key');
      expect(adapter.restoreItem).not.toHaveBeenCalledWith('key2');
    });
  });
});
