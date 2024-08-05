const fs = require('fs');
const path = require('path');
const STUB_ADDRESS = ''.padEnd(43, '1');
/* ao READ-ONLY Env Variables */
const AO_LOADER_HANDLER_ENV = {
  Process: {
    Id: STUB_ADDRESS,
    Owner: STUB_ADDRESS,
    Tags: [{ name: 'Authority', value: 'XXXXXX' }],
  },
  Module: {
    Id: ''.padEnd(43, 'a'),
    Tags: [{ name: 'Authority', value: 'YYYYYY' }],
  },
};

const AO_LOADER_OPTIONS = {
  format: 'wasm64-unknown-emscripten-draft_2024_02_15',
  inputEncoding: 'JSON-1',
  outputEncoding: 'JSON-1',
  memoryLimit: '524288000', // in bytes
  computeLimit: (9e12).toString(),
  extensions: [],
};

const AOS_WASM = fs.readFileSync(
  path.join(
    __dirname,
    'fixtures/aos-cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk.wasm',
  ),
);

const BUNDLED_SOURCE_CODE = fs.readFileSync(
  path.join(__dirname, '../dist/aos-bundled.lua'),
  'utf-8',
);

const DEFAULT_HANDLE_OPTIONS = {
  Id: ''.padEnd(43, '1'),
  ['Block-Height']: '1',
  // important to set the address so that that `Authority` check passes. Else the `isTrusted` with throw an error.
  Owner: STUB_ADDRESS,
  Module: 'ANT',
  Target: ''.padEnd(43, '1'),
  From: STUB_ADDRESS,
  Timestamp: Date.now(),
};

module.exports = {
  BUNDLED_SOURCE_CODE,
  AOS_WASM,
  AO_LOADER_OPTIONS,
  AO_LOADER_HANDLER_ENV,
  STUB_ADDRESS,
  DEFAULT_HANDLE_OPTIONS,
};
