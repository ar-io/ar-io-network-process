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

  // // send a total token supply message
  const totalSupplyRes = await handle(
    bootRes.Memory,
    {
      ...DEFAULT_HANDLE_OPTIONS,
      Id: PROCESS_ID,
      From: PROCESS_ID,
      Tags: [{ name: 'Action', value: 'Total-Supply' }],
    },
    AO_LOADER_HANDLER_ENV,
  );

  return {
    handle,
    memory: totalSupplyRes.Memory,
  };
}

export function assertNoResultError(result) {
  const errorTag = result.Messages?.[0]?.Tags?.find(
    (tag) => tag.name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);
}
