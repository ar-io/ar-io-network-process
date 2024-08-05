const AoLoader = require('@permaweb/ao-loader');
const {
  AOS_WASM,
  AO_LOADER_HANDLER_ENV,
  AO_LOADER_OPTIONS,
  DEFAULT_HANDLE_OPTIONS,
  BUNDLED_SOURCE_CODE,
} = require('../tools/constants');

/**
 * Loads the aos wasm binary and returns the handle function with program memory
 * @returns {Promise<{handle: Function, memory: WebAssembly.Memory}>}
 */
async function createAosLoader() {
  const handle = await AoLoader(AOS_WASM, AO_LOADER_OPTIONS);
  const evalRes = await handle(
    null,
    {
      ...DEFAULT_HANDLE_OPTIONS,
      Tags: [
        { name: 'Action', value: 'Eval' },
        { name: 'Module', value: ''.padEnd(43, '1') },
      ],
      Data: BUNDLED_SOURCE_CODE,
    },
    AO_LOADER_HANDLER_ENV,
  );
  return {
    handle,
    memory: evalRes.Memory,
  };
}

module.exports = {
  createAosLoader,
};
