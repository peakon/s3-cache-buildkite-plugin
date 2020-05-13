const { toCacheKey } = require("./template");

const testfileChecksum =
  "fdb0ca202b94a4b8a8d968aca21a927d52f8da0889b5b3b9abd3b0cb4e097066";

describe("toCacheKey", () => {
  it("returns input string if no templates found", async () => {
    expect(await toCacheKey("foobar")).toEqual("foobar");
  });

  it("ignores for invalid template functions", async () => {
    expect(await toCacheKey('aaa-{{ doesnotexist("aaa") }}')).toEqual("aaa-");
  });

  it("ignores empty templates", async () => {
    expect(await toCacheKey("aaa-{{}}")).toEqual("aaa-");
    expect(await toCacheKey("aaa-{{  }}")).toEqual("aaa-");
  });

  describe("for a template with checksum function", () => {
    it("returns file checksum for correctly formatted template", async () => {
      expect(
        await toCacheKey('{{ checksum "tests/data/testfile.txt" }}')
      ).toEqual(testfileChecksum);
    });

    it("ignores whitespaces inside double curly braces", async () => {
      expect(
        await toCacheKey('{{checksum "tests/data/testfile.txt" }}')
      ).toEqual(testfileChecksum);
      expect(
        await toCacheKey('{{  checksum "tests/data/testfile.txt"   }}')
      ).toEqual(testfileChecksum);
    });

    it("resolves multiple templates", async () => {
      expect(
        await toCacheKey(
          '{{ checksum "tests/data/testfile.txt" }}-{{ checksum "tests/data/testfile.txt" }}'
        )
      ).toEqual(`${testfileChecksum}-${testfileChecksum}`);
    });
  });

  describe("template with epoch function", () => {
    it("adds current time in seconds since epoch", async () => {
      expect(await toCacheKey("{{ epoch }}")).toMatch(/\d{10}/);
    });
  });

  describe("template with .Environment.<var>", () => {
    beforeEach(() => (process.env.FOO = "bar"));
    afterEach(() => delete process.env.FOO);
    it("adds current time in seconds since epoch", async () => {
      expect(await toCacheKey("{{ .Environment.FOO }}")).toEqual("bar");
    });
  });
});
