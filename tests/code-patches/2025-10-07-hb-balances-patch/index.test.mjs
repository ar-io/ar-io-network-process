import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import { assertNoResultError, createAosLoader } from '../../utils.mjs';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_BLOCK_HEIGHT,
  STUB_HASH_CHAIN,
  STUB_TIMESTAMP,
} from '../../../tools/constants.mjs';

const __dirname = path.dirname(new URL(import.meta.url).pathname);

const patchFile = fs.readFileSync(
  path.join(__dirname, '../../../patches/2025-10-07-hb-balances-patch.lua'),
  { encoding: 'utf-8' },
);

const wasmMemory = fs.readFileSync(
  path.join(
    __dirname,
    'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE-2025-10-07-wasm-memory',
  ),
);

const wasm = fs.readFileSync(
  path.join(__dirname, 'CWxzoe4IoNpFHiykadZWphZtLWybDF8ocNi7gmK6zCg.wasm'),
);

const { handle: originalHandle, memory } = await createAosLoader({
  wasm,
  lua: patchFile,
});
const startMemory = memory;

/**
 *
 * @param {{
 *  options: Object,
 *  memory: WebAssembly.Memory,
 *  shouldAssertNoResultError: boolean
 * }} options
 * @returns {Promise<Object>}
 */
async function handle({
  options = {},
  memory = startMemory,
  shouldAssertNoResultError = true,
  timestamp = STUB_TIMESTAMP,
  blockHeight = STUB_BLOCK_HEIGHT,
  hashchain = STUB_HASH_CHAIN,
}) {
  options.Timestamp ??= timestamp;
  options['Block-Height'] ??= blockHeight;
  options['Hash-Chain'] ??= hashchain;
  const result = await originalHandle(
    memory,
    {
      ...DEFAULT_HANDLE_OPTIONS,
      ...options,
    },
    {
      ...AO_LOADER_HANDLER_ENV,
      Process: {
        ...AO_LOADER_HANDLER_ENV.Process,
        Id: 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
        Owner: processOwner,
      },
    },
  );
  if (shouldAssertNoResultError) {
    assertNoResultError(result);
  }
  return result;
}

const processOwner = 'My21NOHZyyeQG0t0yANsWjRakNDM7CJvd8urtdMLEDE';

describe('2025-10-07-hb-balances-patch', () => {
  it('should eval the patch file', async () => {
    const { memory: evalPatchMemory, ...rest } = await handle({
      options: {
        From: processOwner,
        Owner: processOwner,
        Tags: [{ name: 'Action', value: 'Eval' }],
        Data: patchFile,
      },
      memory: wasmMemory,
    });

    console.dir(rest, { depth: null });

    const balances = await handle({
      options: {
        From: processOwner,
        Owner: processOwner,
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      memory: evalPatchMemory,
    });
    console.dir(balances, { depth: null });
  });
});
