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
  STUB_PROCESS_ID,
  INITIAL_OPERATOR_STAKE,
} from '../tools/constants.mjs';

const initialOperatorStake = 100_000_000_000;

export const basePermabuyPrice = 2_500_000_000;
export const baseLeasePriceFor9CharNameFor1Year = 600_000_000;
export const baseLeasePriceFor9CharNameFor3Years = 800_000_000;

export const returnedNamesPeriod = 1000 * 60 * 60 * 24 * 14; // 14 days

export const genesisEpochTimestamp = 1719900000000; // Tuesday, July 2, 2024, 06:00:00 AM UTC
export const epochLength = 1000 * 60 * 60 * 24; // 24 hours
export const distributionDelay = 1000 * 60 * 40; // 40 minutes

export const mARIOPerARIO = 1_000_000;
export const ARIOToMARIO = (amount) => amount * mARIOPerARIO;

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
  timestamp = STUB_TIMESTAMP,
}) {
  options.Timestamp ??= timestamp;

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
  assertValidSupplyEventData(result);
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

export function assertValidSupplyEventData(result) {
  const events = parseEventsFromResult(result);
  for (const event of events) {
    assert(event['_e'] === 1, 'Event flag _e is not the correct value');
    if (event['Total-Token-Supply']) {
      assert.strictEqual(
        event['Total-Token-Supply'],
        1_000_000_000_000_000,
        `Total-Token-Supply is invariant for event for message. Logs:\n${result.Output.data}\n\nEvents:\n${JSON.stringify(events, null, 2)}`,
      );
    }
  }
}

export const getBalances = async ({ memory, timestamp = STUB_TIMESTAMP }) => {
  assert(memory, 'Memory is required');
  const result = await handle({
    options: {
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

export const getBalance = async ({
  address,
  memory,
  timestamp = STUB_TIMESTAMP,
}) => {
  const result = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Balance' },
        { name: 'Address', value: address },
      ],
    },
    timestamp,
    memory,
  });
  // enforce the token.lua "spec" as defined by https://github.com/permaweb/aos/blob/15dd81ee596518e2f44521e973b8ad1ce3ee9945/blueprints/token.lua
  assert(
    ['Action', 'Balance', 'Account', 'Ticker'].every((tag) =>
      result.Messages[0].Tags.map((t) => t.name).includes(tag),
    ),
    `Tags are not in compliance with the token.lua spec. ${JSON.stringify(result.Messages[0].Tags, null, 2)}`,
  );
  assert(
    typeof result.Messages[0].Data === 'string' &&
      !isNaN(Number(result.Messages[0].Data)),
    'Balance is invalid. It is not a string which is out of compliance with the token.lua spec',
  );
  const balance = JSON.parse(result.Messages[0].Data);
  return balance;
};

export const transfer = async ({
  recipient = STUB_ADDRESS,
  quantity = initialOperatorStake,
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
      From: PROCESS_OWNER,
      Owner: PROCESS_OWNER,
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

export const joinNetwork = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  address,
  observerAddress,
  stakeQuantity = INITIAL_OPERATOR_STAKE,
  quantity = 100_000_000_000,
  tags = validGatewayTags({ observerAddress, operatorStake: stakeQuantity }),
}) => {
  const transferMemory = await transfer({
    recipient: address,
    quantity,
    memory,
    timestamp,
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
    timestamp,
  });

  // Stake a gateway for the user to delegate to
  const joinNetworkResult = await joinNetwork({
    memory,
    address: gatewayAddress,
    tags: gatewayTags,
    timestamp: timestamp,
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

export const getDemandFactorSettings = async ({ memory, timestamp }) => {
  const result = await handle({
    options: {
      Tags: [{ name: 'Action', value: 'Demand-Factor-Settings' }],
      Timestamp: timestamp,
    },
    memory,
  });
  return JSON.parse(result.Messages[0].Data);
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

export const getDelegatesItems = async ({
  memory,
  gatewayAddress,
  timestamp = STUB_TIMESTAMP,
}) => {
  const { result } = await getDelegates({
    memory,
    from: STUB_ADDRESS,
    timestamp,
    gatewayAddress,
  });
  assertNoResultError(result);
  return JSON.parse(result.Messages?.[0]?.Data).items;
};

export const getDelegations = async ({ memory, address, timestamp }) => {
  const result = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Paginated-Delegations' },
        { name: 'Address', value: address },
      ],
    },
    memory,
    timestamp,
  });
  return JSON.parse(result.Messages?.[0]?.Data);
};

export const getVaults = async ({
  memory,
  cursor,
  limit,
  sortBy,
  sortOrder,
  timestamp = STUB_TIMESTAMP,
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
      Timestamp: timestamp,
    },
    memory,
  });
  return {
    result: rest,
    memory: Memory,
  };
};

export const getGatewayVaultsItems = async ({
  memory,
  gatewayAddress,
  timestamp = STUB_TIMESTAMP,
}) => {
  const gatewayVaultsResult = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Paginated-Gateway-Vaults' },
        { name: 'Address', value: gatewayAddress },
      ],
      Timestamp: timestamp,
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
    timestamp,
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
    },
    timestamp,
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
  from = PROCESS_OWNER,
  name,
  processId = STUB_PROCESS_ID,
  type = 'lease',
  years = 1,
  timestamp = STUB_TIMESTAMP,
  fundFrom,
  assertError = true,
}) => {
  const buyRecordResult = await handle({
    options: {
      From: from,
      Owner: from,
      Tags: [
        { name: 'Action', value: 'Buy-Name' },
        { name: 'Name', value: name },
        { name: 'Purchase-Type', value: type },
        { name: 'Process-Id', value: processId },
        { name: 'Years', value: `${years}` },
        ...(fundFrom ? [{ name: 'Fund-From', value: fundFrom }] : []),
      ],
    },
    shouldAssertNoResultError: assertError,
    timestamp,
    memory,
  });
  if (assertError) {
    assertNoResultError(buyRecordResult);
  }
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

export const totalTokenSupply = async ({ memory, timestamp = 0 }) => {
  return await handle({
    options: {
      Tags: [
        {
          name: 'Action',
          value: 'Total-Token-Supply',
        },
      ],
      Timestamp: timestamp,
    },
    memory,
  });
};

export const tick = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  forcePrune = false,
}) => {
  const tickResult = await handle({
    options: {
      Tags: [{ name: 'Action', value: 'Tick' }],
      Timestamp: timestamp,
      ...(forcePrune ? { name: 'Force-Prune', value: 'true' } : {}),
    },
    memory,
  });
  return {
    memory: tickResult.Memory,
    result: tickResult,
  };
};

export const getEpoch = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  epochIndex,
}) => {
  const epochResult = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Epoch' },
        ...(epochIndex !== undefined
          ? [{ name: 'Epoch-Index', value: epochIndex }]
          : []),
      ],
      Timestamp: timestamp,
    },
    memory,
  });
  assertNoResultError(epochResult);
  return JSON.parse(epochResult.Messages[0].Data);
};

export const getEpochDistributions = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  epochIndex,
}) => {
  const distributionsResult = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Epoch-Distributions' },
        ...(epochIndex !== undefined
          ? [{ name: 'Epoch-Index', value: epochIndex }]
          : []),
      ],
      Timestamp: timestamp,
    },
    memory,
  });
  return JSON.parse(distributionsResult.Messages[0].Data);
};

export const getPrescribedObservers = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  epochIndex,
}) => {
  const prescribedObserversResult = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Epoch-Prescribed-Observers' },
        ...(epochIndex !== undefined
          ? [{ name: 'Epoch-Index', value: epochIndex }]
          : []),
      ],
      Timestamp: timestamp,
    },
    memory,
  });
  assertNoResultError(prescribedObserversResult);
  return JSON.parse(prescribedObserversResult.Messages[0].Data);
};

export const getPrescribedNames = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
  epochIndex,
}) => {
  const prescribedNamesResult = await handle({
    options: {
      Tags: [
        { name: 'Action', value: 'Epoch-Prescribed-Names' },
        ...(epochIndex !== undefined
          ? [{ name: 'Epoch-Index', value: epochIndex }]
          : []),
      ],
      Timestamp: timestamp,
    },
    memory,
  });
  assertNoResultError(prescribedNamesResult);
  return JSON.parse(prescribedNamesResult.Messages[0].Data);
};

export const getEpochSettings = async ({
  memory,
  timestamp = STUB_TIMESTAMP,
}) => {
  const epochSettingsResult = await handle({
    options: {
      Tags: [{ name: 'Action', value: 'Epoch-Settings' }],
      Timestamp: timestamp,
    },
    memory,
  });
  assertNoResultError(epochSettingsResult);
  return JSON.parse(epochSettingsResult.Messages[0].Data);
};
