import assert from 'node:assert';
import { createAosLoader } from './utils.mjs';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  PROCESS_OWNER,
  STUB_OPERATOR_ADDRESS,
  STUB_TIMESTAMP,
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
  quantity = 100_000_000_000,
}) => {
  // give them the join network token amount
  const transferMemory = await transfer({
    recipient: address,
    quantity,
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

export const setUpStake = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  gatewayAddress = STUB_OPERATOR_ADDRESS,
  gatewayTags = validGatewayTags,
  stakerAddress = STUB_ADDRESS,
  transferQty,
  stakeQty,
  additionalStakingTags = [],
}) => {
  // Send IO to the user to delegate stake
  memory = await transfer({
    recipient: stakerAddress,
    quantity: transferQty,
    memory,
    cast: true,
  });

  // Stake a gateway for the user to delegate to
  const joinNetworkResult = await joinNetwork({
    memory,
    address: gatewayAddress,
    tags: gatewayTags,
    timestamp: timestamp - 1,
  });
  assertNoResultError(joinNetworkResult);
  memory = joinNetworkResult.memory;

  const stakeResult = await handle(
    {
      From: stakerAddress,
      Owner: stakerAddress,
      Tags: [
        { name: 'Action', value: 'Delegate-Stake' },
        { name: 'Quantity', value: `${stakeQty}` },
        { name: 'Address', value: gatewayAddress },
        ...additionalStakingTags,
      ],
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(stakeResult);
  return {
    memory: stakeResult.Memory,
    result: stakeResult,
  };
};
