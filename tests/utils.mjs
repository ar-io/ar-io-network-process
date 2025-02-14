import AoLoader from '@permaweb/ao-loader';
import {
  AOS_WASM,
  AO_LOADER_HANDLER_ENV,
  AO_LOADER_OPTIONS,
  DEFAULT_HANDLE_OPTIONS,
  BUNDLED_SOURCE_CODE,
  PROCESS_ID,
} from '../tools/constants.mjs';
import assert from 'node:assert';

/**
 * Loads the aos wasm binary and returns the handle function with program memory
 * @returns {Promise<{handle: Function, memory: WebAssembly.Memory}>}
 */
export async function createAosLoader() {
  const handle = await AoLoader(AOS_WASM, AO_LOADER_OPTIONS);
  const bootRes = await handle(
    null,
    {
      ...DEFAULT_HANDLE_OPTIONS,
      Id: PROCESS_ID,
      From: PROCESS_ID,
      Tags: [{ name: 'Type', value: 'Process' }],
    },
    AO_LOADER_HANDLER_ENV,
  );

  return {
    handle,
    memory: bootRes.Memory,
  };
}

export function assertNoResultError(result) {
  const errorTag = result.Messages?.[0]?.Tags?.find(
    (tag) => tag.name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);
}
