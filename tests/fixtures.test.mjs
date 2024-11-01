// these are wrappers of handlers with safe inputs for testing
import assert from 'node:assert';
import { AO_LOADER_HANDLER_ENV, PROCESS_ID } from '../tools/constants.mjs';
import { createAosLoader } from './utils.mjs';

const { handle: originalHandle, memory: startMemory } = await createAosLoader();
export const handle = (options = {}, mem = startMemory) => {
  return originalHandle(mem, options, AO_LOADER_HANDLER_ENV);
};

// all the actions you can take on a gateway
export const delegateStake = async ({
  quantity,
  sharedMemory,
  gateway = STUB_ADDRESS,
  delegator = 'stub-delegator-address-'.padEnd(43, 'x'),
}) => {
  const transferMemory = await transfer({
    recipient: delegator,
    quantity: quantity,
    memory: sharedMemory,
  });

  const delegateStakeResult = await handle(
    {
      From: delegator,
      Owner: delegator,
      Tags: [
        { name: 'Action', value: 'Delegate-Stake' },
        { name: 'Quantity', value: quantity }, // 2K IO
        { name: 'Address', value: gateway }, // our gateway address
      ],
      Timestamp: STUB_TIMESTAMP + 1,
    },
    transferMemory,
  );
  // assert no error tag
  const errorTag = delegateStakeResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    result: delegateStakeResult,
    memory: delegateStakeResult.Memory,
    delegator,
    gateway,
  };
};

export const decreaseDelegateStake = async ({
  quantity,
  memory,
  timestamp,
  gateway = STUB_ADDRESS,
  delegator = 'stub-delegator-address-'.padEnd(43, 'x'),
}) => {
  const vaultId = ''.padEnd(43, 'x');
  const decreaseStakeResult = await handle(
    {
      From: delegator,
      Owner: delegator,
      Timestamp: timestamp,
      Id: vaultId,
      Tags: [
        { name: 'Action', value: 'Decrease-Delegate-Stake' },
        { name: 'Address', value: gateway },
        { name: 'Quantity', value: `${quantity}` }, // 500 IO
      ],
    },
    memory,
  );

  const errorTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    result: decreaseStakeResult,
    memory: decreaseStakeResult.Memory,
    vaultId,
    delegator,
    gateway,
  };
};

export const cancelWithdrawal = async ({
  memory,
  timestamp,
  address,
  vaultId,
}) => {
  await handle(
    {
      From: address,
      Owner: address,
      Timestamp: timestamp,
      Tags: [
        { name: 'Action', value: 'Cancel-Withdrawal' },
        { name: 'Address', value: address },
        { name: 'Vault-Id', value: vaultId },
      ],
    },
    memory,
  );

  const errorTag = cancelWithdrawalResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    memory: cancelWithdrawalResult.Memory,
    result: cancelWithdrawalResult,
  };
};

export const getGateway = async ({ memory, timestamp, address }) => {
  const gateway = await handle(
    {
      Tags: [
        { name: 'Action', value: 'Gateway' },
        { name: 'Address', value: address },
      ],
      Timestamp: timestamp,
    },
    memory,
  );

  console.log(gateway.Messages[0]);

  const errorTag = gateway.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    gateway: JSON.parse(gateway.Messages[0].Data),
    memory: gateway.Memory,
  };
};

export const joinNetwork = async ({ memory, address, timestamp }) => {
  const joinNetworkResult = await handle(
    {
      From: address,
      Owner: address,
      Tags: [
        { name: 'Action', value: 'Join-Network' },
        { name: 'Label', value: 'test-gateway' },
        { name: 'Note', value: 'test-note' },
        { name: 'FQDN', value: 'test-fqdn' },
        { name: 'Operator-Stake', value: `${100_000_000_000}` }, // 100K IO
        { name: 'Port', value: '443' },
        { name: 'Protocol', value: 'https' },
        { name: 'Allow-Delegated-Staking', value: 'true' },
        { name: 'Min-Delegated-Stake', value: '500000000' }, // 500 IO
        { name: 'Delegate-Reward-Share-Ratio', value: '25' }, // 25% go to the delegates
        { name: 'Observer-Address', value: address },
        {
          name: 'Properties',
          value: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
        },
        { name: 'Auto-Stake', value: 'true' },
      ],
      Timestamp: timestamp,
    },
    memory,
  );

  console.log(joinNetworkResult.Messages);

  const errorTag = joinNetworkResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    memory: joinNetworkResult.Memory,
    result: joinNetworkResult,
  };
};

export const leaveNetwork = async ({ memory, address }) => {
  const leaveNetworkResult = await handle(
    {
      From: address,
      Owner: address,
      Tags: [{ name: 'Action', value: 'Leave-Network' }],
    },
    memory,
  );

  const errorTag = leaveNetworkResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    memory: leaveNetworkResult.Memory,
    result: leaveNetworkResult,
  };
};

export const updateGatewaySettings = async ({ memory, address, settings }) => {
  const updateGatewaySettingsResult = await handle(
    {
      From: address,
      Owner: address,
      Tags: settings,
    },
    memory,
  );

  const errorTag = updateGatewaySettingsResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    memory: updateGatewaySettingsResult.Memory,
    result: updateGatewaySettingsResult,
  };
};

export const transfer = async ({
  from = PROCESS_ID,
  recipient = STUB_ADDRESS,
  quantity = initialOperatorStake,
  memory,
} = {}) => {
  const transferResult = await handle(
    {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Transfer' },
        { name: 'Recipient', value: recipient },
        { name: 'Quantity', value: quantity },
        { name: 'Cast', value: false },
      ],
    },
    memory,
  );

  // assert no error tag
  const errorTag = transferResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    memory: transferResult.Memory,
    result: transferResult,
  };
};

export const increaseOperatorStake = async ({
  quantity,
  memory,
  address = STUB_ADDRESS,
}) => {
  const increaseStakeResult = await handle(
    {
      From: address,
      Owner: address,
      Tags: [
        { name: 'Action', value: 'Increase-Operator-Stake' },
        { name: 'Quantity', value: quantity.toString() }, // 10K IO
      ],
    },
    memory,
  );

  const errorTag = increaseStakeResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.Name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);

  return {
    memory: increaseStakeResult.Memory,
    result: increaseStakeResult,
  };
};
