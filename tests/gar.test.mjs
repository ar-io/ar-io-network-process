import { createAosLoader } from './utils.mjs';
import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_TIMESTAMP,
  STUB_MESSAGE_ID,
  STUB_ADDRESS,
  PROCESS_OWNER,
  validGatewayTags,
  PROCESS_ID,
} from '../tools/constants.mjs';

const initialOperatorStake = 100_000_000_000;
const delegatorAddress = 'delegator-address-'.padEnd(43, 'x');

describe('GatewayRegistry', async () => {
  const { handle: originalHandle, memory: startMemory } =
    await createAosLoader();
  let sharedMemory = startMemory; // memory we'll use across unique tests;
  async function handle(options = {}, mem = sharedMemory) {
    return originalHandle(
      mem,
      {
        ...DEFAULT_HANDLE_OPTIONS,
        ...options,
      },
      AO_LOADER_HANDLER_ENV,
    );
  }

  const transfer = async ({
    recipient = STUB_ADDRESS,
    quantity = initialOperatorStake,
    memory = sharedMemory,
  } = {}) => {
    const transferResult = await handle(
      {
        From: PROCESS_OWNER,
        Owner: PROCESS_OWNER,
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
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return transferResult.Memory;
  };

  const delegateStake = async ({
    memory,
    timestamp,
    delegatorAddress,
    quantity,
    gatewayAddress,
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

    // assert no error tag
    const errorTag = delegateResult.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      result: delegateResult,
      memory: delegateResult.Memory,
    };
  };

  const getBalances = async ({ memory }) => {
    const result = await handle(
      {
        Tags: [{ name: 'Action', value: 'Balances' }],
      },
      memory,
    );

    const balances = JSON.parse(result.Messages?.[0]?.Data);
    return balances;
  };

  const getGateway = async ({
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

  const joinNetwork = async ({
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

    // assert no error
    const errorTag = joinNetworkResult.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      memory: joinNetworkResult.Memory,
      result: joinNetworkResult,
    };
  };

  const decreaseOperatorStake = async ({
    memory,
    decreaseQty,
    address,
    instant = false,
    messageId = STUB_MESSAGE_ID,
    timestamp = STUB_TIMESTAMP,
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

    // assert no error
    const errorTag = result.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      memory: result.Memory,
      result,
    };
  };

  const decreaseDelegateStake = async ({
    memory,
    gatewayAddress,
    delegatorAddress,
    decreaseQty,
    instant = false,
    messageId,
    timestamp = STUB_TIMESTAMP,
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

    // assert no error
    const errorTag = result.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      memory: result.Memory,
      result,
    };
  };

  const cancelWithdrawal = async ({
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

    // assert no error
    const errorTag = result.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      memory: result.Memory,
      result,
    };
  };

  const instantWithdrawal = async ({
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

    // assert no error
    const errorTag = result.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      memory: result.Memory,
      result,
    };
  };

  const increaseOperatorStake = async ({
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

    // assert no error
    const errorTag = result.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      memory: result.Memory,
      result,
    };
  };

  const leaveNetwork = async ({
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

    // assert no error
    const errorTag = result.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      memory: result.Memory,
      result,
    };
  };

  const updateGatewaySettings = async ({
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

    // assert no error
    const errorTag = result.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return {
      memory: result.Memory,
      result,
    };
  };

  before(async () => {
    const { memory: joinNetworkMemory } = await joinNetwork({
      address: STUB_ADDRESS,
      memory: sharedMemory,
    });
    // NOTE: all tests will start with this gateway joined to the network - use `sharedMemory` for the first interaction for each test to avoid having to join the network again
    sharedMemory = joinNetworkMemory;
  });

  describe('Join-Network', () => {
    it('should allow joining of the network record', async () => {
      // check the gateway record from contract
      const gateway = await getGateway({
        address: STUB_ADDRESS,
        memory: sharedMemory,
      });
      assert.deepEqual(gateway, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 100_000_000_000, // matches the initial operator stake from the test setup
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: STUB_TIMESTAMP,
        settings: {
          label: 'test-gateway',
          note: 'test-note',
          fqdn: 'test-fqdn',
          port: 443,
          protocol: 'https',
          allowDelegatedStaking: true,
          minDelegatedStake: 500_000_000,
          delegateRewardShareRatio: 25,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          autoStake: true,
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
      });
    });
  });

  describe('Leave-Network', () => {
    it('should allow leaving the network and vault operator stake correctly', async () => {
      // gateway before leaving
      const gateway = await getGateway({
        memory: sharedMemory,
        address: STUB_ADDRESS,
      });

      // leave at timestamp
      const leavingTimestamp = STUB_TIMESTAMP + 1500;
      const { memory: leaveNetworkMemory } = await leaveNetwork({
        address: STUB_ADDRESS,
        memory: sharedMemory,
        timestamp: leavingTimestamp,
      });

      // gateway after
      const leavingGateway = await getGateway({
        memory: leaveNetworkMemory,
        address: STUB_ADDRESS,
      });
      assert.deepStrictEqual(leavingGateway, {
        ...gateway,
        operatorStake: 0,
        totalDelegatedStake: 0,
        status: 'leaving',
        delegates: [],
        endTimestamp: leavingTimestamp + 1000 * 60 * 60 * 24 * 90, // 90 days
        vaults: {
          '2222222222222222222222222222222222222222222': {
            balance: 50000000000,
            endTimestamp: 7797601500, // 90 days for the minimum operator stake
            startTimestamp: leavingTimestamp,
          },
          mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm: {
            balance: 50000000000,
            endTimestamp: 2613601500, // 30 days for the remaining stake
            startTimestamp: leavingTimestamp,
          },
        },
      });
    });
  });

  describe('Update-Gateway-Settings', () => {
    it('should allow updating the gateway settings', async () => {
      // gateway before
      const gateway = await getGateway({
        address: STUB_ADDRESS,
        memory: sharedMemory,
      });

      const { memory: updatedSettingsMemory } = await updateGatewaySettings({
        memory: sharedMemory,
        address: STUB_ADDRESS,
        settingsTags: [
          { name: 'Action', value: 'Update-Gateway-Settings' },
          { name: 'Label', value: 'new-label' },
          { name: 'Note', value: 'new-note' },
          { name: 'FQDN', value: 'new-fqdn' },
          { name: 'Port', value: '80' },
          { name: 'Protocol', value: 'https' },
          { name: 'Allow-Delegated-Staking', value: 'false' },
          { name: 'Min-Delegated-Stake', value: '1000000000' }, // 1K IO
          { name: 'Delegate-Reward-Share-Ratio', value: '10' },
          {
            name: 'Properties',
            value: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          },
          { name: 'Auto-Stake', value: 'false' },
        ],
      });

      // check the gateway record from contract
      const updatedGateway = await getGateway({
        address: STUB_ADDRESS,
        memory: updatedSettingsMemory,
      });

      // should match old gateway, with new settings
      assert.deepStrictEqual(updatedGateway, {
        ...gateway,
        settings: {
          label: 'new-label',
          note: 'new-note',
          fqdn: 'new-fqdn',
          port: 80,
          protocol: 'https',
          autoStake: false,
          allowDelegatedStaking: false,
          minDelegatedStake: 1_000_000_000,
          delegateRewardShareRatio: 10,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
        },
      });
    });
  });

  describe('Increase-Operator-Stake', () => {
    it('should allow increasing operator stake', async () => {
      // gateway before
      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: sharedMemory,
      });
      const increaseQty = 10_000_000_000;
      const { memory: increaseStakeMemory } = await increaseOperatorStake({
        address: STUB_ADDRESS,
        increaseQty,
        memory: sharedMemory,
      });

      // check the gateway record from contract
      const updatedGateway = await getGateway({
        address: STUB_ADDRESS,
        memory: increaseStakeMemory,
      });
      assert.deepStrictEqual(updatedGateway, {
        ...gatewayBefore,
        operatorStake: 100_000_000_000 + increaseQty, // matches the initial operator stake from the test setup plus the increase
      });
    });
  });

  describe('Decrease-Operator-Stake', () => {
    // join the network and then increase stake
    it('should allow decreasing the operator stake if the remaining stake is above the minimum', async () => {
      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: sharedMemory,
      });

      const decreaseQty = 10_000_000_000;
      const decreaseTimestamp = STUB_TIMESTAMP + 1500;
      const decreaseMessageId = 'decrease-operator-stake-message-'.padEnd(
        43,
        '1',
      );
      const { memory: decreaseStakeMemory } = await decreaseOperatorStake({
        address: STUB_ADDRESS,
        timestamp: decreaseTimestamp,
        memory: sharedMemory,
        messageId: decreaseMessageId,
        decreaseQty,
      });

      const updatedGateway = await getGateway({
        address: STUB_ADDRESS,
        memory: decreaseStakeMemory,
      });
      assert.deepStrictEqual(updatedGateway, {
        ...gatewayBefore,
        operatorStake: 100_000_000_000 - decreaseQty, // matches the initial operator stake from the test setup minus the decrease
        vaults: {
          [decreaseMessageId]: {
            balance: decreaseQty,
            startTimestamp: decreaseTimestamp,
            endTimestamp: decreaseTimestamp + 1000 * 60 * 60 * 24 * 30, // should be 30 days for anything above the minimum
          },
        },
      });
    });

    it('should allow decreasing the operator stake instantly, for a fee', async () => {
      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: sharedMemory,
      });
      const balancesBefore = await getBalances({
        memory: sharedMemory,
      });
      const decreaseQty = 5_000_000_000;
      const decreaseMessageId = 'decrease-stake-instantly-'.padEnd(43, 'x');
      const { memory: decreaseInstantMemory, result: decreaseInstantResult } =
        await decreaseOperatorStake({
          address: STUB_ADDRESS,
          decreaseQty,
          memory: sharedMemory,
          messageId: decreaseMessageId,
          instant: true,
        });

      const gatewayAfter = await getGateway({
        address: STUB_ADDRESS,
        memory: decreaseInstantMemory,
      });

      assert.deepStrictEqual(gatewayAfter, {
        ...gatewayBefore,
        operatorStake: 100_000_000_000 - decreaseQty, // initial stake minus full decrease qty
        vaults: [], // no vaults bc it was instant
      });

      // validate the tags exist
      const tags = {};
      for (const expectedTag of [
        'Penalty-Rate',
        'Expedited-Withdrawal-Fee',
        'Amount-Withdrawn',
      ]) {
        const tag = decreaseInstantResult.Messages?.[0]?.Tags?.find(
          (tag) => tag.name === expectedTag,
        );
        assert(tag, `${expectedTag} did not exist on instant operator stake`);
        tags[expectedTag] = tag.value;
      }

      const penaltyRate = +tags['Penalty-Rate'];
      const amountWithdrawn = +tags['Amount-Withdrawn'];
      const instantWithdrawalFee = +tags['Expedited-Withdrawal-Fee'];
      const expectedPenaltyRate = 0.5; // the maximum penalty rate for an expedited withdrawal
      const expectedExpeditedWithdrawalFee = Math.floor(
        decreaseQty * expectedPenaltyRate,
      );
      const expectedAmountWithdrawn =
        decreaseQty - expectedExpeditedWithdrawalFee;
      // Assert correct values for penalty rate, expedited withdrawal fee, and amount withdrawn
      assert.equal(penaltyRate, expectedPenaltyRate);
      assert.equal(amountWithdrawn, expectedAmountWithdrawn);
      assert.equal(instantWithdrawalFee, expectedExpeditedWithdrawalFee);
      // validate the balances moved from the gateway, to the operator and protocol balance
      const balancesAfter = await getBalances({
        memory: decreaseInstantMemory,
      });
      const expectedProtocolBalance =
        balancesBefore[PROCESS_ID] + instantWithdrawalFee;
      const expectedOperatorBalance =
        balancesBefore[STUB_ADDRESS] + amountWithdrawn;
      assert.equal(balancesAfter[PROCESS_ID], expectedProtocolBalance);
      assert.equal(balancesAfter[STUB_ADDRESS], expectedOperatorBalance);
    });
  });

  describe('Delegate-Stake', () => {
    it('should allow delegated staking to an existing gateway', async () => {
      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: sharedMemory,
      });
      const delegatedQty = 500_000_000;
      const delegationTimestamp = gatewayBefore.startTimestamp + 1500; // after the gateway has joined
      const { memory: delegatedStakeMemory } = await delegateStake({
        delegatorAddress,
        quantity: delegatedQty,
        gatewayAddress: STUB_ADDRESS,
        timestamp: delegationTimestamp,
        memory: sharedMemory,
      });

      // check the gateway record from contract
      const gatewayAfter = await getGateway({
        address: STUB_ADDRESS,
        memory: delegatedStakeMemory,
      });
      assert.deepStrictEqual(gatewayAfter, {
        ...gatewayBefore,
        totalDelegatedStake: delegatedQty,
        delegates: {
          [delegatorAddress]: {
            delegatedStake: delegatedQty,
            startTimestamp: delegationTimestamp,
            vaults: [],
          },
        },
      });
    });
  });

  describe('Decrease-Delegate-Stake', () => {
    it('should allow withdrawing a delegated stake from a gateway', async () => {
      const decreaseStakeTimestamp = STUB_TIMESTAMP + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const stakeQty = 10000000000;
      const decreaseQty = stakeQty / 2;
      const decreaseStakeMsgId = 'decrease-stake-message-id-'.padEnd(43, 'x');
      const { memory: delegatedStakeMemory } = await delegateStake({
        delegatorAddress,
        quantity: stakeQty,
        gatewayAddress: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });
      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: delegatedStakeMemory,
      });
      const { memory: decreaseStakeMemory } = await decreaseDelegateStake({
        memory: delegatedStakeMemory,
        delegatorAddress,
        decreaseQty,
        timestamp: decreaseStakeTimestamp,
        gatewayAddress: STUB_ADDRESS,
        messageId: decreaseStakeMsgId,
      });
      // get the gateway record
      const gatewayAfter = await getGateway({
        address: STUB_ADDRESS,
        memory: decreaseStakeMemory,
      });
      assert.deepStrictEqual(gatewayAfter, {
        ...gatewayBefore,
        totalDelegatedStake: gatewayBefore.totalDelegatedStake - decreaseQty,
        delegates: {
          [delegatorAddress]: {
            delegatedStake: stakeQty - decreaseQty,
            startTimestamp: STUB_TIMESTAMP,
            vaults: {
              [decreaseStakeMsgId]: {
                balance: decreaseQty,
                startTimestamp: decreaseStakeTimestamp, // 15 minutes after stubbedTimestamp
                endTimestamp: decreaseStakeTimestamp + 1000 * 60 * 60 * 24 * 30, // 30 days
              },
            },
          },
        },
      });
    });
  });

  describe('Cancel-Withdrawal', () => {
    it('should allow cancelling a delegate withdrawal', async () => {
      const decreaseStakeTimestamp = STUB_TIMESTAMP + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const stakeQty = 10000000000;
      const decreaseQty = stakeQty / 2;
      const decreaseStakeMsgId = 'decrease-stake-message-id-'.padEnd(43, 'x');
      const { memory: delegatedStakeMemory } = await delegateStake({
        delegatorAddress,
        quantity: stakeQty,
        gatewayAddress: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });
      // get the gateway before the delegation and cancellation
      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: delegatedStakeMemory,
      });

      const { memory: decreaseStakeMemory } = await decreaseDelegateStake({
        memory: delegatedStakeMemory,
        delegatorAddress,
        decreaseQty,
        timestamp: decreaseStakeTimestamp,
        gatewayAddress: STUB_ADDRESS,
        messageId: decreaseStakeMsgId,
      });
      const { memory: cancelWithdrawalMemory } = await cancelWithdrawal({
        vaultOwner: delegatorAddress,
        gatewayAddress: STUB_ADDRESS,
        vaultId: decreaseStakeMsgId,
        memory: decreaseStakeMemory,
        timestamp: decreaseStakeTimestamp,
      });
      // get the gateway record
      const gatewayAfter = await getGateway({
        address: STUB_ADDRESS,
        memory: cancelWithdrawalMemory,
      });
      // no changes to the gateway after a withdrawal is cancelled
      assert.deepStrictEqual(gatewayAfter, gatewayBefore);
    });
    it('should allow cancelling an operator withdrawal', async () => {
      const decreaseStakeTimestamp = STUB_TIMESTAMP + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const stakeQty = 10000000000;
      const decreaseQty = stakeQty / 2;
      const decreaseStakeMsgId = 'decrease-stake-message-id-'.padEnd(43, 'x');
      // get the gateway before the delegation and cancellation
      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: sharedMemory,
      });

      const { memory: decreaseStakeMemory } = await decreaseOperatorStake({
        memory: sharedMemory,
        address: STUB_ADDRESS,
        decreaseQty,
        timestamp: decreaseStakeTimestamp,
        messageId: decreaseStakeMsgId,
      });
      const { memory: cancelWithdrawalMemory } = await cancelWithdrawal({
        vaultOwner: STUB_ADDRESS,
        gatewayAddress: STUB_ADDRESS,
        vaultId: decreaseStakeMsgId,
        memory: decreaseStakeMemory,
        timestamp: decreaseStakeTimestamp,
      });
      // get the gateway record
      const gatewayAfter = await getGateway({
        address: STUB_ADDRESS,
        memory: cancelWithdrawalMemory,
      });
      // no changes to the gateway after a withdrawal is cancelled
      assert.deepStrictEqual(gatewayAfter, gatewayBefore);
    });
  });

  describe('Instant-Withdrawal', () => {
    it('should allow a delegate to decrease stake instantly, for a fee', async () => {
      const stakeQty = 500000000;
      const { memory: delegatedStakeMemory } = await delegateStake({
        delegatorAddress,
        quantity: stakeQty,
        gatewayAddress: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
      });

      // create the vault by decreasing stake
      const decreaseStakeMsgId = 'decrease-stake-message-id-'.padEnd(43, 'x');
      const { memory: decreaseStakeMemory } = await decreaseDelegateStake({
        memory: delegatedStakeMemory,
        delegatorAddress,
        decreaseQty: stakeQty, // withdrawal the entire stake
        timestamp: STUB_TIMESTAMP,
        gatewayAddress: STUB_ADDRESS,
        messageId: decreaseStakeMsgId,
      });

      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: decreaseStakeMemory,
      });

      const balancesBefore = await getBalances({
        memory: decreaseStakeMemory,
      });

      const { memory: instantWithdrawalMemory } = await instantWithdrawal({
        memory: decreaseStakeMemory,
        address: delegatorAddress,
        gatewayAddress: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP, // how much time as passed since the vault was created
        vaultId: decreaseStakeMsgId,
      });

      const gatewayAfter = await getGateway({
        address: STUB_ADDRESS,
        memory: instantWithdrawalMemory,
      });

      const balancesAfter = await getBalances({
        memory: instantWithdrawalMemory,
      });

      assert.deepStrictEqual(gatewayAfter, {
        ...gatewayBefore,
        totalDelegatedStake: 0, // the entire stake was withdrawn
        delegates: [], // the delegate is removed
      });
      // validate the withdrawal went to the delegate balance and the penalty went to the protocol
      const withdrawalAmount = stakeQty * 0.5; // half the penalty
      const penaltyAmount = stakeQty * 0.5; // half the penalty
      assert.deepEqual(
        balancesAfter[delegatorAddress],
        balancesBefore[delegatorAddress] + withdrawalAmount,
      ); // half the penalty
      assert.deepEqual(
        balancesAfter[PROCESS_ID],
        balancesBefore[PROCESS_ID] + penaltyAmount,
      ); // original stake + penalty
    });
  });
  // save observations
  describe('Save-Observations', () => {
    it('should save observations', async () => {
      // Steps: add a gateway, create the first epoch to prescribe it, submit an observation from the gateway, tick to the epoch distribution timestamp, check the rewards were distributed correctly
    });
  });
});
