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

export const basePermabuyPrice = 2_500_000_000;
export const baseLeasePrice = 600_000_000;

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

export const getBalances = async ({ memory, timestamp = STUB_TIMESTAMP }) => {
  const result = await handle(
    {
      Tags: [{ name: 'Action', value: 'Balances' }],
      Timestamp: timestamp,
    },
    memory,
  );

  const balances = JSON.parse(result.Messages?.[0]?.Data);
  return balances;
};

export const getBalance = async ({
  address,
  memory,
  timestamp = STUB_TIMESTAMP,
}) => {
  const balances = await getBalances({ memory, timestamp });
  return balances[address];
};

export const transfer = async ({
  recipient = STUB_ADDRESS,
  quantity = initialOperatorStake,
  memory = startMemory,
  cast = false,
} = {}) => {
  if (quantity === 0) {
    // Nothing to do
    return memory;
  }

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

export const getBaseRegistrationFeeForName = async ({
  memory,
  timestamp,
  name = 'great-nam',
}) => {
  const result = await handle(
    {
      Tags: [{ name: 'Action', value: 'Get-Registration-Fees' }],
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(result);
  return JSON.parse(result.Messages[0].Data)[name.length.toString()]['lease'][
    '1'
  ];
};

export const getDemandFactor = async ({ memory, timestamp }) => {
  const result = await handle(
    {
      Tags: [{ name: 'Action', value: 'Demand-Factor' }],
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(result);
  return result.Messages[0].Data;
};

export const getDelegates = async ({
  memory,
  from,
  timestamp,
  gatewayAddress,
}) => {
  const delegatesResult = await handle(
    {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Paginated-Delegates' },
        { name: 'Address', value: gatewayAddress },
      ],
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(delegatesResult);
  return {
    result: delegatesResult,
    memory: delegatesResult.Memory,
  };
};

export const getDelegatesItems = async ({ memory, gatewayAddress }) => {
  const { result } = await getDelegates({
    memory,
    from: STUB_ADDRESS,
    timestamp: STUB_TIMESTAMP,
    gatewayAddress,
  });
  return JSON.parse(result.Messages?.[0]?.Data).items;
};

export const getDelegations = async ({ memory, address }) => {
  const result = await handle(
    {
      Tags: [
        { name: 'Action', value: 'Paginated-Delegations' },
        { name: 'Address', value: address },
      ],
    },
    memory,
  );
  assertNoResultError(result);
  return JSON.parse(result.Messages?.[0]?.Data);
};

export const getVaults = async ({
  memory,
  cursor,
  limit,
  sortBy,
  sortOrder,
}) => {
  const { Memory, ...rest } = await handle(
    {
      Tags: [
        { name: 'Action', value: 'Paginated-Vaults' },
        ...(cursor ? [{ name: 'Cursor', value: cursor }] : []),
        ...(limit ? [{ name: 'Limit', value: limit }] : []),
        ...(sortBy ? [{ name: 'Sort-By', value: sortBy }] : []),
        ...(sortOrder ? [{ name: 'Sort-Order', value: sortOrder }] : []),
      ],
    },
    memory,
  );
  return {
    result: rest,
    memory: Memory,
  };
};

export const getGatewayVaultsItems = async ({ memory, gatewayAddress }) => {
  const gatewayVaultsResult = await handle(
    {
      Tags: [
        { name: 'Action', value: 'Paginated-Gateway-Vaults' },
        { name: 'Address', value: gatewayAddress },
      ],
    },
    memory,
  );
  assertNoResultError(gatewayVaultsResult);
  return JSON.parse(gatewayVaultsResult.Messages?.[0]?.Data).items;
};

export const delegateStake = async ({
  memory,
  timestamp,
  delegatorAddress,
  quantity,
  gatewayAddress,
  assert = true,
}) => {
  // give the wallet the delegate tokens
  const transferMemory = await transfer({
    recipient: delegatorAddress,
    quantity,
    memory,
  });

  const delegateResult = await handle(
    {
      From: delegatorAddress,
      Owner: delegatorAddress,
      Tags: [
        { name: 'Action', value: 'Delegate-Stake' },
        { name: 'Quantity', value: `${quantity}` }, // 2K IO
        { name: 'Address', value: gatewayAddress }, // our gateway address
      ],
      Timestamp: timestamp,
    },
    transferMemory,
  );
  if (assert) {
    assertNoResultError(delegateResult);
  }
  return {
    result: delegateResult,
    memory: delegateResult.Memory,
  };
};

export const getGateway = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  address,
}) => {
  const gatewayResult = await handle(
    {
      Tags: [
        { name: 'Action', value: 'Gateway' },
        { name: 'Address', value: address },
      ],
      Timestamp: timestamp,
    },
    memory,
  );
  const gateway = JSON.parse(gatewayResult.Messages?.[0]?.Data);
  return gateway;
};

export const getAllowedDelegates = async ({
  memory,
  from,
  timestamp,
  gatewayAddress,
}) => {
  const delegatesResult = await handle(
    {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Paginated-Allowed-Delegates' },
        { name: 'Address', value: gatewayAddress },
      ],
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(delegatesResult);

  return {
    result: delegatesResult,
    memory: delegatesResult.Memory,
  };
};

export const getAllowedDelegatesItems = async ({ memory, gatewayAddress }) => {
  const { result } = await getAllowedDelegates({
    memory,
    from: STUB_ADDRESS,
    timestamp: STUB_TIMESTAMP,
    gatewayAddress,
  });
  return JSON.parse(result.Messages?.[0]?.Data)?.items;
};

export const decreaseOperatorStake = async ({
  memory,
  decreaseQty,
  address,
  instant = false,
  messageId = STUB_MESSAGE_ID,
  timestamp = STUB_TIMESTAMP,
  assert = true,
}) => {
  const result = await handle(
    {
      From: address,
      Owner: address,
      Timestamp: timestamp,
      Id: messageId,
      Tags: [
        { name: 'Action', value: 'Decrease-Operator-Stake' },
        { name: 'Quantity', value: `${decreaseQty}` },
        { name: 'Instant', value: `${instant}` },
      ],
    },
    memory,
  );
  if (assert) {
    assertNoResultError(result);
  }
  return {
    memory: result.Memory,
    result,
  };
};

export const decreaseDelegateStake = async ({
  memory,
  gatewayAddress,
  delegatorAddress,
  decreaseQty,
  instant = false,
  messageId,
  timestamp = STUB_TIMESTAMP,
  assert = true,
}) => {
  const result = await handle(
    {
      From: delegatorAddress,
      Owner: delegatorAddress,
      Timestamp: timestamp,
      Id: messageId,
      Tags: [
        { name: 'Action', value: 'Decrease-Delegate-Stake' },
        { name: 'Address', value: gatewayAddress },
        { name: 'Quantity', value: `${decreaseQty}` }, // 500 IO
        { name: 'Instant', value: `${instant}` },
      ],
    },
    memory,
  );
  if (assert) {
    assertNoResultError(result);
  }
  return {
    memory: result.Memory,
    result,
  };
};

export const cancelWithdrawal = async ({
  memory,
  vaultOwner,
  gatewayAddress,
  timestamp = STUB_TIMESTAMP,
  vaultId,
}) => {
  const result = await handle(
    {
      From: vaultOwner,
      Owner: vaultOwner,
      Tags: [
        { name: 'Action', value: 'Cancel-Withdrawal' },
        { name: 'Vault-Id', value: vaultId },
        { name: 'Address', value: gatewayAddress },
      ],
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(result);
  return {
    memory: result.Memory,
    result,
  };
};

export const instantWithdrawal = async ({
  memory,
  address,
  timestamp = STUB_TIMESTAMP,
  gatewayAddress,
  vaultId,
}) => {
  const result = await handle(
    {
      From: address,
      Owner: address,
      Tags: [
        { name: 'Action', value: 'Instant-Withdrawal' },
        { name: 'Address', value: gatewayAddress },
        { name: 'Vault-Id', value: vaultId },
      ],
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(result);
  return {
    memory: result.Memory,
    result,
  };
};

export const increaseOperatorStake = async ({
  address,
  increaseQty,
  timestamp = STUB_TIMESTAMP,
  memory,
}) => {
  // give them the stake they are increasing by
  const transferMemory = await transfer({
    memory,
    quantity: increaseQty,
    recipient: address,
  });
  const result = await handle(
    {
      From: address,
      Owner: address,
      Tags: [
        { name: 'Action', value: 'Increase-Operator-Stake' },
        { name: 'Quantity', value: `${increaseQty}` },
      ],
      Timestamp: timestamp,
    },
    transferMemory,
  );
  assertNoResultError(result);
  return {
    memory: result.Memory,
    result,
  };
};

export const leaveNetwork = async ({
  address,
  timestamp = STUB_TIMESTAMP,
  memory,
}) => {
  const result = await handle(
    {
      From: address,
      Owner: address,
      Tags: [{ name: 'Action', value: 'Leave-Network' }],
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(result);
  return {
    memory: result.Memory,
    result,
  };
};

export const updateGatewaySettings = async ({
  address,
  settingsTags,
  timestamp = STUB_TIMESTAMP,
  memory,
}) => {
  const result = await handle(
    {
      From: address,
      Owner: address,
      Tags: settingsTags,
      Timestamp: timestamp,
    },
    memory,
  );
  assertNoResultError(result);
  return {
    memory: result.Memory,
    result,
  };
};

export const buyRecord = async ({
  memory,
  from,
  name,
  processId,
  type = 'lease',
  years = 1,
}) => {
  const buyRecordResult = await handle(
    {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Buy-Record' },
        { name: 'Name', value: name },
        { name: 'Purchase-Type', value: type },
        { name: 'Process-Id', value: processId },
        { name: 'Years', value: `${years}` },
      ],
    },
    memory,
  );
  assertNoResultError(buyRecordResult);
  return {
    result: buyRecordResult,
    memory: buyRecordResult.Memory,
  };
};
