"use strict";

const fs = require("fs-extra");
const S3CacheAdapter = require("./s3-cache-adapter");

const adapter = new S3CacheAdapter("buildkite-cache");

function cleanTempDir() {
  if (fs.existsSync(".tmp")) {
    fs.emptyDirSync(".tmp");
    fs.rmdirSync(".tmp");
  }
}

function prepareTempDir() {
  cleanTempDir();
  fs.copySync("tests/data", ".tmp");
}

function pathExists(filePath) {
  return fs.existsSync(filePath);
}

describe("S3CacheAdapter", () => {
  afterEach(() => {
    cleanTempDir();
  });

  it("saves and restores single file", async () => {
    prepareTempDir();
    await adapter.saveItem("singlefile", [".tmp/testfile.txt"]);

    cleanTempDir();
    await adapter.restoreItem("singlefile");
    expect(pathExists(".tmp/testfile.txt")).toBe(true);
    expect(pathExists(".tmp/testfile2.txt")).toBe(false);
    expect(pathExists(".tmp/subfolder/testfile.txt")).toBe(false);
  });

  it("saves and restores a directory", async () => {
    prepareTempDir();
    await adapter.saveItem("dir", [".tmp"]);

    cleanTempDir();
    await adapter.restoreItem("dir");
    expect(pathExists(".tmp/testfile.txt")).toBe(true);
    expect(pathExists(".tmp/testfile2.txt")).toBe(true);
    expect(pathExists(".tmp/subfolder/testfile.txt")).toBe(true);
  });

  it("saves and restores multiple files", async () => {
    prepareTempDir();
    await adapter.saveItem("multiple-files", [
      ".tmp/testfile.txt",
      ".tmp/subfolder/testfile.txt",
    ]);

    cleanTempDir();
    await adapter.restoreItem("multiple-files");
    expect(pathExists(".tmp/testfile.txt")).toBe(true);
    expect(pathExists(".tmp/testfile2.txt")).toBe(false);
    expect(pathExists(".tmp/subfolder/testfile.txt")).toBe(true);
  });

  it("saves and restores files and dirs", async () => {
    prepareTempDir();
    await adapter.saveItem("files-and-dirs", [
      ".tmp/testfile.txt",
      ".tmp/subfolder",
    ]);

    cleanTempDir();
    await adapter.restoreItem("files-and-dirs");
    expect(pathExists(".tmp/testfile.txt")).toBe(true);
    expect(pathExists(".tmp/testfile2.txt")).toBe(false);
    expect(pathExists(".tmp/subfolder/testfile.txt")).toBe(true);
  });

  it("saves and restores overlapping dirs", async () => {
    prepareTempDir();
    await adapter.saveItem("overlapping-dirs", [".tmp", ".tmp/subfolder"]);

    cleanTempDir();
    await adapter.restoreItem("overlapping-dirs");
    expect(pathExists(".tmp/testfile.txt")).toBe(true);
    expect(pathExists(".tmp/testfile2.txt")).toBe(true);
    expect(pathExists(".tmp/subfolder/testfile.txt")).toBe(true);
  });

  it("ignores missing dirs", async () => {
    prepareTempDir();
    await adapter.saveItem("existing-and-missing-dir", [
      ".tmp/subfolder",
      ".tmp/missing",
    ]);

    cleanTempDir();
    await adapter.restoreItem("existing-and-missing-dir");
    expect(pathExists(".tmp/testfile.txt")).toBe(false);
    expect(pathExists(".tmp/testfile2.txt")).toBe(false);
    expect(pathExists(".tmp/missing")).toBe(false);
    expect(pathExists(".tmp/subfolder/testfile.txt")).toBe(true);
  });
});
