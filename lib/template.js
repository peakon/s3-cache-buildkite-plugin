"use strict";

const crypto = require("crypto");
const fs = require("fs");
const stringReplaceAsync = require("string-replace-async");

const TEMPLATE_FUNCTIONS = [
  {
    test: /checksum\s*['"]{1}(.*)['"]{1}\s*/,
    apply: async (filePath) => {
      return new Promise(function (resolve, reject) {
        const hash = crypto.createHash("sha256");
        const input = fs.createReadStream(filePath);

        input.on("error", reject);

        input.on("data", function (chunk) {
          hash.update(chunk);
        });

        input.on("close", function () {
          resolve(hash.digest("hex"));
        });
      });
    },
  },
  {
    test: /epoch/,
    apply: () => {
      return Math.round(new Date().getTime() / 1000);
    },
  },
  {
    test: /\.Environment\.(.*)/,
    apply: (envVar) => {
      return process.env[envVar];
    },
  },
];

module.exports = {
  async toCacheKey(template) {
    return stringReplaceAsync(
      template,
      /(\{\{\s?(.*?)\s?\}\})/g,
      async function (_textToReplace, _, fnString) {
        const fn = TEMPLATE_FUNCTIONS.find((f) => f.test.test(fnString));
        if (fn) {
          const [, ...args] = fnString.match(fn.test);
          const result = await fn.apply(...args);
          return result;
        } else {
          return "";
        }
      }
    );
  },
};
