import assert from 'node:assert';
import { createAosLoader } from './utils.mjs';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  PROCESS_OWNER,
  STUB_OPERATOR_ADDRESS,
  STUB_TIMESTAMP,
  STUB_MESSAGE_ID,
  validGatewayTags,
} from '../tools/constants.mjs';

const initialOperatorStake = 100_000_000_000;

export const basePermabuyPrice = 2_500_000_000;
export const baseLeasePriceFor9CharNameFor1Year = 600_000_000;
export const baseLeasePriceFor9CharNameFor3Years = 800_000_000;

export const returnedNamesPeriod = 1000 * 60 * 60 * 24 * 14; // 14 days

export const genesisEpochTimestamp = 1719900000000; // Tuesday, July 2, 2024, 06:00:00 AM UTC
export const epochLength = 1000 * 60 * 60 * 24; // 24 hours
export const distributionDelay = 1000 * 60 * 40; // 40 minutes

const { handle: originalHandle, memory } = await createAosLoader();
export const startMemory = memory;

/**
 *
 * @param {{
 *  options: Object,
 *  memory: WebAssembly.Memory,
 *  shouldAssertNoResultError: boolean
 * }} options
 * @returns {Promise<Object>}
 */
export async function handle({
  options = {},
  memory = startMemory,
  shouldAssertNoResultError = true,
}) {
  const result = await originalHandle(
    memory,
    {
      ...DEFAULT_HANDLE_OPTIONS,
      ...options,
    },
    AO_LOADER_HANDLER_ENV,
  );
  if (shouldAssertNoResultError) {
    assertNoResultError(result);
  }
  return result;
}

export function assertNoResultError(result) {
  const errorTag = result.Messages?.[0]?.Tags?.find(
    (tag) => tag.name === 'Error',
  );
  assert.strictEqual(errorTag, undefined);
}

export function parseEventsFromResult(result) {
  return (
    result?.Output?.data
      ?.split('\n')
      ?.filter((line) => line.trim().startsWith('{"'))
      ?.map((line) => {
        try {
          return JSON.parse(line);
        } catch (e) {
          return {};
        }
      })
      ?.filter((event) => Object.keys(event).length && event['_e']) || []
  );
}

export const getBalances = async ({ memory, timestamp = STUB_TIMESTAMP }) => {
  const result = await handle({
    options: {
      Tags: [{ name: 'Action', value: 'Balances' }],
      Timestamp: timestamp,
    },
    memory,
  });

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

  const transferResult = await handle({
    options: {
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
  });
  return transferResult.Memory;
};

export const joinNetwork = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  address,
  observerAddress,
  tags = validGatewayTags({ observerAddress }),
  quantity = 100_000_000_000,
}) => {
  // give them the join network token amount
  const transferMemory = await transfer({
    recipient: address,
    quantity,
    memory,
  });
  const joinNetworkResult = await handle({
    options: {
      From: address,
      Owner: address,
      Tags: tags,
      Timestamp: timestamp,
    },
    memory: transferMemory,
  });
  return {
    memory: joinNetworkResult.Memory,
    result: joinNetworkResult,
  };
};

export const setUpStake = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  gatewayAddress = STUB_OPERATOR_ADDRESS,
  gatewayTags = validGatewayTags(),
  stakerAddress = STUB_ADDRESS,
  transferQty,
  stakeQty,
  additionalStakingTags = [],
}) => {
  // Send ARIO to the user to delegate stake
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

  const stakeResult = await handle({
    options: {
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
  });
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
  const result = await handle({
    options: {
      Tags: [{ name: 'Action', value: 'Get-Registration-Fees' }],
      Timestamp: timestamp,
    },
    memory,
  });
  return JSON.parse(result.Messages[0].Data)[name.length.toString()]['lease'][
    '1'
  ];
};

export const getDemandFactor = async ({ memory, timestamp }) => {
  const result = await handle({
    options: {
      Tags: [{ name: 'Action', value: 'Demand-Factor' }],
      Timestamp: timestamp,
    },
    memory,
  });
  return result.Messages[0].Data;
};

export const getDelegates = async ({
  memory,
  from,
  timestamp,
  gatewayAddress,
}) => {
  const delegatesResult = await handle({
    options: {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Paginated-Delegates' },
        { name: 'Address', value: gatewayAddress },
      ],
      Timestamp: timestamp,
    },
    memory,
  });
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
  const result = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Paginated-Delegations' },
        { name: 'Address', value: address },
      ],
    },
    memory,
  });
  return JSON.parse(result.Messages?.[0]?.Data);
};

export const getVaults = async ({
  memory,
  cursor,
  limit,
  sortBy,
  sortOrder,
}) => {
  const { Memory, ...rest } = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Paginated-Vaults' },
        ...(cursor ? [{ name: 'Cursor', value: cursor }] : []),
        ...(limit ? [{ name: 'Limit', value: limit }] : []),
        ...(sortBy ? [{ name: 'Sort-By', value: sortBy }] : []),
        ...(sortOrder ? [{ name: 'Sort-Order', value: sortOrder }] : []),
      ],
    },
    memory,
  });
  return {
    result: rest,
    memory: Memory,
  };
};

export const getGatewayVaultsItems = async ({ memory, gatewayAddress }) => {
  const gatewayVaultsResult = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Paginated-Gateway-Vaults' },
        { name: 'Address', value: gatewayAddress },
      ],
    },
    memory,
  });
  return JSON.parse(gatewayVaultsResult.Messages?.[0]?.Data).items;
};

export const createVault = async ({
  memory,
  quantity,
  lockLengthMs,
  from = PROCESS_OWNER,
  msgId = STUB_MESSAGE_ID,
  timestamp = STUB_TIMESTAMP,
  shouldAssertNoResultError = true,
}) => {
  const createVaultResult = await handle({
    options: {
      Id: msgId,
      From: from,
      Owner: from,
      Timestamp: timestamp,
      Tags: [
        {
          name: 'Action',
          value: 'Create-Vault',
        },
        {
          name: 'Quantity',
          value: quantity.toString(),
        },
        {
          name: 'Lock-Length',
          value: lockLengthMs.toString(),
        },
      ],
    },
    memory,
    shouldAssertNoResultError,
  });

  return { result: createVaultResult, memory: createVaultResult.Memory };
};

export const createVaultedTransfer = async ({
  memory,
  quantity,
  lockLengthMs,
  recipient,
  allowUnsafeAddresses,
  msgId = STUB_MESSAGE_ID,
  timestamp = STUB_TIMESTAMP,
  from = PROCESS_OWNER,
  shouldAssertNoResultError = true,
}) => {
  const createVaultedTransferResult = await handle({
    options: {
      Id: msgId,
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Vaulted-Transfer' },
        { name: 'Recipient', value: recipient },
        { name: 'Quantity', value: quantity.toString() },
        { name: 'Lock-Length', value: lockLengthMs.toString() },
        ...(allowUnsafeAddresses !== undefined
          ? [
              {
                name: 'Allow-Unsafe-Addresses',
                value: allowUnsafeAddresses.toString(),
              },
            ]
          : []),
      ],
      Timestamp: timestamp,
    },
    memory,
    shouldAssertNoResultError,
  });
  return {
    result: createVaultedTransferResult,
    memory: createVaultedTransferResult.Memory,
  };
};

export const delegateStake = async ({
  memory,
  timestamp,
  delegatorAddress,
  quantity,
  gatewayAddress,
  shouldAssertNoResultError = true,
}) => {
  // give the wallet the delegate tokens
  const transferMemory = await transfer({
    recipient: delegatorAddress,
    quantity,
    memory,
  });

  const delegateResult = await handle({
    options: {
      From: delegatorAddress,
      Owner: delegatorAddress,
      Tags: [
        { name: 'Action', value: 'Delegate-Stake' },
        { name: 'Quantity', value: `${quantity}` }, // 2K ARIO
        { name: 'Address', value: gatewayAddress }, // our gateway address
      ],
      Timestamp: timestamp,
    },
    memory: transferMemory,
    shouldAssertNoResultError,
  });
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
  const gatewayResult = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Gateway' },
        { name: 'Address', value: address },
      ],
      Timestamp: timestamp,
    },
    memory,
  });
  const gateway = JSON.parse(gatewayResult.Messages?.[0]?.Data);
  return gateway;
};

export const getAllowedDelegates = async ({
  memory,
  from,
  timestamp,
  gatewayAddress,
}) => {
  const delegatesResult = await handle({
    options: {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Paginated-Allowed-Delegates' },
        { name: 'Address', value: gatewayAddress },
      ],
      Timestamp: timestamp,
    },
    memory,
  });

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
  shouldAssertNoResultError = true,
}) => {
  const result = await handle({
    options: {
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
    shouldAssertNoResultError,
  });

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
  shouldAssertNoResultError = true,
}) => {
  const result = await handle({
    options: {
      From: delegatorAddress,
      Owner: delegatorAddress,
      Timestamp: timestamp,
      Id: messageId,
      Tags: [
        { name: 'Action', value: 'Decrease-Delegate-Stake' },
        { name: 'Address', value: gatewayAddress },
        { name: 'Quantity', value: `${decreaseQty}` }, // 500 ARIO
        { name: 'Instant', value: `${instant}` },
      ],
    },
    memory,
    shouldAssertNoResultError,
  });

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
  const result = await handle({
    options: {
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
  });
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
  const result = await handle({
    options: {
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
  });
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
  const result = await handle({
    options: {
      From: address,
      Owner: address,
      Tags: [
        { name: 'Action', value: 'Increase-Operator-Stake' },
        { name: 'Quantity', value: `${increaseQty}` },
      ],
      Timestamp: timestamp,
    },
    memory: transferMemory,
  });
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
  const result = await handle({
    options: {
      From: address,
      Owner: address,
      Tags: [{ name: 'Action', value: 'Leave-Network' }],
      Timestamp: timestamp,
    },
    memory,
  });
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
  const result = await handle({
    options: {
      From: address,
      Owner: address,
      Tags: settingsTags,
      Timestamp: timestamp,
    },
    memory,
  });
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
  timestamp = STUB_TIMESTAMP,
}) => {
  const buyRecordResult = await handle({
    options: {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Buy-Record' },
        { name: 'Name', value: name },
        { name: 'Purchase-Type', value: type },
        { name: 'Process-Id', value: processId },
        { name: 'Years', value: `${years}` },
      ],
      Timestamp: timestamp,
    },
    memory,
  });
  return {
    result: buyRecordResult,
    memory: buyRecordResult.Memory,
  };
};

export const saveObservations = async ({
  from = STUB_ADDRESS,
  timestamp = STUB_TIMESTAMP,
  shouldAssertNoResultError = true,
  failedGateways = 'failed-gateway-'.padEnd(43, 'e'),
  reportTxId = 'report-tx-id-'.padEnd(43, 'f'),
  memory = startMemory,
}) => {
  const result = await handle({
    options: {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Save-Observations' },
        { name: 'Report-Tx-Id', value: reportTxId },
        { name: 'Failed-Gateways', value: failedGateways },
      ],
      Timestamp: timestamp,
    },
    memory,
    shouldAssertNoResultError,
  });
  return {
    memory: result.Memory,
    result,
  };
};
