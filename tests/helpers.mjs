import assert from 'node:assert';
import { createAosLoader } from './utils.mjs';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  STUB_TIMESTAMP,
  PROCESS_OWNER,
  validGatewayTags,
} from '../tools/constants.mjs';

const initialOperatorStake = 100_000_000_000;

const { handle: originalHandle, memory } = await createAosLoader();
export const startMemory = memory;

export async function handle(options = {}, mem = startMemory) {
  return originalHandle(
    mem,
    {
      ...DEFAULT_HANDLE_OPTIONS,
      ...options,
    },
    AO_LOADER_HANDLER_ENV,
  );
}

export function assertNoResultError(result) {
  const errorTag = result.Messages?.[0]?.Tags?.find(
    (tag) => tag.name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);
}

export const transfer = async ({
  recipient = STUB_ADDRESS,
  quantity = initialOperatorStake,
  memory = startMemory,
  cast = false,
} = {}) => {
  const transferResult = await handle(
    {
      From: PROCESS_OWNER,
      Owner: PROCESS_OWNER,
      Tags: [
        { name: 'Action', value: 'Transfer' },
        { name: 'Recipient', value: recipient },
        { name: 'Quantity', value: quantity },
        { name: 'Cast', value: cast },
      ],
    },
    memory,
  );
  assertNoResultError(transferResult);
  return transferResult.Memory;
};

export const joinNetwork = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  address,
  tags = validGatewayTags,
}) => {
  // give them the join network token amount
  const transferMemory = await transfer({
    recipient: address,
    quantity: 100_000_000_000,
    memory,
  });
  const joinNetworkResult = await handle(
    {
      From: address,
      Owner: address,
      Tags: tags,
      Timestamp: timestamp,
    },
    transferMemory,
  );
  assertNoResultError(joinNetworkResult);
  return {
    memory: joinNetworkResult.Memory,
    result: joinNetworkResult,
  };
};
