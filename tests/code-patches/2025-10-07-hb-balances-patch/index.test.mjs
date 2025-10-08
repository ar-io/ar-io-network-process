import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import { assertNoResultError, createAosLoader } from '../../utils.mjs';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  INITIAL_OPERATOR_STAKE,
  STUB_ADDRESS,
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
  //  lua: patchFile,
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
  timestamp = Date.now().toString(),
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
      Target: 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
    },
    {
      ...AO_LOADER_HANDLER_ENV,
      Process: {
        ...AO_LOADER_HANDLER_ENV.Process,
        Id: 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
        Tags: [
          ...AO_LOADER_HANDLER_ENV.Process.Tags,
          {
            name: 'Authority',
            value: 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY',
          },
        ],
      },
    },
  );
  if (shouldAssertNoResultError) {
    assertNoResultError(result);
  }
  return result;
}

const processOwner = 'My21NOHZyyeQG0t0yANsWjRakNDM7CJvd8urtdMLEDE';
const processId = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE';
const authority = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY';

const transfer = async ({
  recipient = STUB_ADDRESS,
  quantity = INITIAL_OPERATOR_STAKE,
  memory = startMemory,
  cast = false,
  timestamp = STUB_TIMESTAMP,
} = {}) => {
  if (quantity === 0) {
    // Nothing to do
    return memory;
  }

  const transferResult = await handle({
    options: {
      From: processId,
      Owner: authority,
      Tags: [
        { name: 'Action', value: 'Transfer' },
        { name: 'Recipient', value: recipient },
        { name: 'Quantity', value: quantity },
        { name: 'Cast', value: cast },
      ],
      Timestamp: timestamp,
    },
    memory,
  });
  assertNoResultError(transferResult);
  return transferResult.Memory;
};

export const getBalances = async ({ memory, timestamp = STUB_TIMESTAMP }) => {
  // assert(memory, 'Memory is required');
  const result = await handle({
    options: {
      From: processId,
      Owner: authority,
      Tags: [{ name: 'Action', value: 'Balances' }],
    },
    timestamp,
    memory,
  });

  const balancesData = result.Messages?.[0]?.Data;
  if (!balancesData) {
    const { Memory, ...rest } = result;
    assert(false, `Something went wrong: ${JSON.stringify(rest, null, 2)}`);
  }
  const balances = JSON.parse(result.Messages?.[0]?.Data);
  return balances;
};

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

    console.log(evalPatchMemory);

    const balances = await handle({
      options: {
        From: processOwner,
        Owner: processOwner,
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      memory: undefined,
    });

    console.dir(balances, { depth: null });
  });

  //   describe('hyperbeam patch balances', async () => {
  //     it('should handle sending a patch to a newly created address', async () => {
  //       const sender = STUB_ADDRESS;
  //       const recipient = ''.padEnd(43, 'a');
  //       const quantity = 100000000;
  //       const transferToSenderAddressMemory = await transfer({
  //         recipient: sender,
  //         quantity,
  //       });
  //       const transferToRecipientAddress = await handle({
  //         options: {
  //           From: sender,
  //           Owner: sender,
  //           Tags: [
  //             { name: 'Action', value: 'Transfer' },
  //             { name: 'Recipient', value: recipient },
  //             { name: 'Quantity', value: String(quantity / 2) },
  //           ],
  //           Timestamp: STUB_TIMESTAMP,
  //         },
  //         memory: transferToSenderAddressMemory,
  //       });
  //       console.dir(transferToRecipientAddress, { depth: null });
  //       const patchMessage = transferToRecipientAddress.Messages.at(-1);
  //       const patchData = patchMessage.Tags.find(
  //         (tag) => tag.name === 'balances',
  //       ).value;
  //       assert.equal(patchData[sender], quantity / 2);
  //       assert.equal(patchData[recipient], quantity / 2);
  //     });

  //     it('should handle sending a patch that drains an address', async () => {
  //       const sender = STUB_ADDRESS;
  //       const recipient = ''.padEnd(43, 'a');
  //       const quantity = 100000000;
  //       const transferToSenderAddressMemory = await transfer({
  //         recipient: sender,
  //         quantity,
  //       });
  //       const balancesAfterTransfer = await getBalances({
  //         memory: transferToSenderAddressMemory,
  //       });
  //       console.dir(balancesAfterTransfer, { depth: null });
  //       const transferToRecipientAddress = await handle({
  //         options: {
  //           From: sender,
  //           Owner: sender,
  //           Tags: [
  //             { name: 'Action', value: 'Transfer' },
  //             { name: 'Recipient', value: recipient },
  //             { name: 'Quantity', value: String(quantity / 2) },
  //           ],
  //           Timestamp: STUB_TIMESTAMP,
  //         },
  //         memory: transferToSenderAddressMemory,
  //       });
  //       const balancesAfterTransferToRecipient = await getBalances({
  //         memory: transferToRecipientAddress.Memory,
  //       });
  //       const patchMessage = transferToRecipientAddress.Messages.at(-1);
  //       const patchData = patchMessage.Tags.find(
  //         (tag) => tag.name === 'balances',
  //       ).value;
  //       assert.equal(patchData[sender], quantity / 2);
  //       assert.equal(patchData[recipient], quantity / 2);

  //       const transferToDrainerAddress = await handle({
  //         options: {
  //           From: sender,
  //           Owner: sender,
  //           Tags: [
  //             { name: 'Action', value: 'Transfer' },
  //             { name: 'Recipient', value: recipient },
  //             { name: 'Quantity', value: String(quantity / 2) },
  //           ],
  //           Timestamp: STUB_TIMESTAMP,
  //         },
  //         memory: transferToRecipientAddress.Memory,
  //       });
  //       const balancesAfterDrain = await getBalances({
  //         memory: transferToDrainerAddress.Memory,
  //       });

  //       const patchMessage2 = transferToDrainerAddress.Messages.at(-1);
  //       const patchData2 = patchMessage2.Tags.find(
  //         (tag) => tag.name === 'balances',
  //       ).value;
  //       assert.equal(patchData2[sender], 0);
  //       assert.equal(patchData2[recipient], quantity);
  //     });

  //     it('should handle sending a patch when an address is removed from balances', async () => {
  //       const sender = STUB_ADDRESS;
  //       const recipient = ''.padEnd(43, 'a');
  //       const quantity = 100000000;
  //       const transferToSenderAddressMemory = await transfer({
  //         recipient: sender,
  //         quantity,
  //       });
  //       const transferToRecipientAddress = await handle({
  //         options: {
  //           From: sender,
  //           Owner: sender,
  //           Tags: [
  //             { name: 'Action', value: 'Transfer' },
  //             { name: 'Recipient', value: recipient },
  //             { name: 'Quantity', value: String(quantity / 2) },
  //           ],
  //           Timestamp: STUB_TIMESTAMP,
  //         },
  //         memory: transferToSenderAddressMemory,
  //       });
  //       const patchMessage = transferToRecipientAddress.Messages.at(-1);
  //       const patchData = patchMessage.Tags.find(
  //         (tag) => tag.name === 'balances',
  //       ).value;
  //       assert.equal(patchData[sender], quantity / 2);
  //       assert.equal(patchData[recipient], quantity / 2);

  //       const transferToDrainerAddress = await handle({
  //         options: {
  //           From: sender,
  //           Owner: sender,
  //           Tags: [
  //             { name: 'Action', value: 'Transfer' },
  //             { name: 'Recipient', value: recipient },
  //             { name: 'Quantity', value: String(quantity / 2) },
  //           ],
  //           Timestamp: STUB_TIMESTAMP,
  //         },
  //         memory: transferToRecipientAddress.Memory,
  //       });

  //       const patchMessage2 = transferToDrainerAddress.Messages.at(-1);
  //       const patchData2 = patchMessage2.Tags.find(
  //         (tag) => tag.name === 'balances',
  //       ).value;
  //       assert.equal(patchData2[sender], 0);
  //       assert.equal(patchData2[recipient], quantity);

  //       const balancesBeforeCleanup = await getBalances({
  //         memory: transferToDrainerAddress.Memory,
  //       });

  //       const tokenSupplyRes = await handle({
  //         options: {
  //           Tags: [{ name: 'Action', value: 'Total-Supply' }],
  //         },
  //         memory: transferToDrainerAddress.Memory,
  //       });
  //       const balancesAfterCleanup = await getBalances({
  //         memory: tokenSupplyRes.Memory,
  //       });

  //       const patchMessage3 = tokenSupplyRes.Messages.at(-1);
  //       const patchData3 = patchMessage3.Tags.find(
  //         (tag) => tag.name === 'balances',
  //       ).value;
  //       assert.equal(patchData3[sender], 0);
  //     });
  //   });
});
