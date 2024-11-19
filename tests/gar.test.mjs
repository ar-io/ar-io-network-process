import {
  assertNoResultError,
  handle,
  joinNetwork,
  startMemory,
  transfer,
  getBalances,
  getDelegatesItems,
  getGatewayVaultsItems,
} from './helpers.mjs';
import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import {
  STUB_TIMESTAMP,
  STUB_MESSAGE_ID,
  STUB_ADDRESS,
  validGatewayTags,
  PROCESS_ID,
} from '../tools/constants.mjs';

const delegatorAddress = 'delegator-address-'.padEnd(43, 'x');

describe('GatewayRegistry', async () => {
  const STUB_ADDRESS_6 = ''.padEnd(43, '6');
  const STUB_ADDRESS_7 = ''.padEnd(43, '7');
  const STUB_ADDRESS_8 = ''.padEnd(43, '8');
  const STUB_ADDRESS_9 = ''.padEnd(43, '9');

  let sharedMemory = startMemory; // memory we'll use across unique tests;

  const delegateStake = async ({
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

  const getAllowedDelegates = async ({
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

  const getAllowedDelegatesItems = async ({ memory, gatewayAddress }) => {
    const { result } = await getAllowedDelegates({
      memory,
      from: STUB_ADDRESS,
      timestamp: STUB_TIMESTAMP,
      gatewayAddress,
    });
    return JSON.parse(result.Messages?.[0]?.Data)?.items;
  };

  const decreaseOperatorStake = async ({
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

  const decreaseDelegateStake = async ({
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
    assertNoResultError(result);
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
    assertNoResultError(result);
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
    assertNoResultError(result);
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
    assertNoResultError(result);
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
    assertNoResultError(result);
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
      assert.deepStrictEqual(gateway, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 100_000_000_000, // matches the initial operator stake from the test setup
        totalDelegatedStake: 0,
        status: 'joined',
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
        weights: {
          stakeWeight: 0,
          tenureWeight: 0,
          gatewayRewardRatioWeight: 0,
          observerRewardRatioWeight: 0,
          compositeWeight: 0,
          normalizedCompositeWeight: 0,
        },
      });
    });

    async function allowlistJoinTest({
      gatewayAddress,
      tags,
      delegateAddresses,
      expectedAllowDelegatedStaking,
      expectedAllowedDelegatesLookup,
      expectedDelegates,
    }) {
      gatewayAddress = gatewayAddress || ''.padEnd(43, '3');
      // give the wallet the joining tokens
      const transferMemory = await transfer({
        recipient: gatewayAddress,
        quantity: 100_000_000_000,
        sharedMemory,
      });

      const tagNames = tags.map((tag) => tag.name);
      const joinNetworkTags = validGatewayTags.filter(
        (tag) => ![...tagNames, 'Observer-Address'].includes(tag.name),
      );
      const { memory: joinNetworkMemory } = await joinNetwork({
        address: gatewayAddress,
        memory: transferMemory,
        tags: [
          ...joinNetworkTags,
          { name: 'Observer-Address', value: gatewayAddress },
          ...tags,
        ],
      });

      // check the gateway record from contract
      const gateway = await getGateway({
        address: gatewayAddress,
        memory: joinNetworkMemory,
      });
      assert.deepEqual(gateway, {
        observerAddress: gatewayAddress,
        operatorStake: 100_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        startTimestamp: STUB_TIMESTAMP,
        settings: {
          label: 'test-gateway',
          note: 'test-note',
          fqdn: 'test-fqdn',
          port: 443,
          protocol: 'https',
          allowDelegatedStaking: expectedAllowDelegatedStaking,
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
        weights: {
          stakeWeight: 0,
          tenureWeight: 0,
          gatewayRewardRatioWeight: 0,
          observerRewardRatioWeight: 0,
          compositeWeight: 0,
          normalizedCompositeWeight: 0,
        },
      });
      const allowedDelegatesResult = await getAllowedDelegates({
        memory: joinNetworkMemory,
        from: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP,
        gatewayAddress: gatewayAddress,
      });
      assert.deepEqual(
        Object.keys(expectedAllowedDelegatesLookup || []).sort(),
        JSON.parse(
          allowedDelegatesResult.result.Messages?.[0]?.Data,
        )?.items?.sort(),
      );

      var returnMemory = joinNetworkMemory;
      if (delegateAddresses && expectedDelegates) {
        var nextMemory = joinNetworkMemory;
        for (const delegateAddress of delegateAddresses) {
          const maybeDelegateResult = await delegateStake({
            memory: nextMemory,
            timestamp: STUB_TIMESTAMP,
            delegatorAddress: delegateAddress,
            quantity: 500_000_000,
            gatewayAddress: gatewayAddress,
          }).catch(() => {});
          if (maybeDelegateResult?.memory) {
            nextMemory = maybeDelegateResult.memory;
          }
        }
        const updatedGatewayDelegates = await getDelegatesItems({
          memory: nextMemory,
          gatewayAddress: gatewayAddress,
        });
        assert.deepEqual(
          updatedGatewayDelegates
            .map((delegateItem) => delegateItem.address)
            .sort(),
          expectedDelegates.slice().sort(),
        );
        returnMemory = nextMemory;
      }
      return returnMemory;
    }

    it('should allow joining of the network with an allow list', async () => {
      const otherGatewayAddress = ''.padEnd(43, '3');
      const updatedMemory = await allowlistJoinTest({
        gatewayAddress: otherGatewayAddress,
        tags: [
          { name: 'Allow-Delegated-Staking', value: 'allowlist' },
          {
            name: 'Allowed-Delegates',
            value: [STUB_ADDRESS_9, STUB_ADDRESS_8].join(','),
          },
        ],
        expectedAllowDelegatedStaking: true,
        expectedAllowedDelegatesLookup: {
          [STUB_ADDRESS_9]: true,
          [STUB_ADDRESS_8]: true,
        },
        delegateAddresses: [STUB_ADDRESS_9, STUB_ADDRESS_7],
        expectedDelegates: [STUB_ADDRESS_9],
      });

      const delegateItems = await getDelegatesItems({
        memory: updatedMemory,
        gatewayAddress: otherGatewayAddress,
      });
      assert.deepEqual(
        [
          {
            startTimestamp: STUB_TIMESTAMP,
            delegatedStake: 500_000_000,
            vaults: [],
            address: STUB_ADDRESS_9,
          },
        ],
        delegateItems,
      );

      const { result: getAllowedDelegatesResult } = await getAllowedDelegates({
        memory: updatedMemory,
        from: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP,
        gatewayAddress: otherGatewayAddress,
      });
      assert.deepEqual(
        JSON.parse(getAllowedDelegatesResult.Messages?.[0]?.Data),
        {
          limit: 100,
          totalItems: 2,
          hasMore: false,
          items: [STUB_ADDRESS_9, STUB_ADDRESS_8],
          sortOrder: 'desc',
        },
      );
    });

    it('should join the network ignoring the allow list if Allow-Delegated-Staking is set to "true"', async () => {
      await allowlistJoinTest({
        tags: [
          { name: 'Allow-Delegated-Staking', value: 'true' },
          { name: 'Allowed-Delegates', value: STUB_ADDRESS },
        ],
        expectedAllowDelegatedStaking: true,
        expectedAllowedDelegatesLookup: undefined,
        delegateAddresses: [STUB_ADDRESS, STUB_ADDRESS_9],
        expectedDelegates: [STUB_ADDRESS, STUB_ADDRESS_9],
      });
    });

    it('should join the network ignoring the allow list if Allow-Delegated-Staking is set to "false"', async () => {
      await allowlistJoinTest({
        tags: [
          { name: 'Allow-Delegated-Staking', value: 'false' },
          { name: 'Allowed-Delegates', value: STUB_ADDRESS },
        ],
        expectedAllowDelegatedStaking: false,
        delegateAddresses: [STUB_ADDRESS],
        expectedAllowedDelegatesLookup: undefined,
        expectedDelegates: [],
      });
    });

    it('should join the network and start an empty allow list if Allow-Delegated-Staking is set to "allowlist"', async () => {
      await allowlistJoinTest({
        tags: [{ name: 'Allow-Delegated-Staking', value: 'allowlist' }],
        expectedAllowDelegatedStaking: true,
        delegateAddresses: [STUB_ADDRESS], // this delegate will be denied
        expectedAllowedDelegatesLookup: [],
        expectedDelegates: [],
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
        endTimestamp: leavingTimestamp + 1000 * 60 * 60 * 24 * 90, // 90 days
      });

      assert.deepStrictEqual(
        await getGatewayVaultsItems({
          memory: leaveNetworkMemory,
          gatewayAddress: STUB_ADDRESS,
        }),
        [
          {
            vaultId: '2222222222222222222222222222222222222222222',
            cursorId: `2222222222222222222222222222222222222222222_${leavingTimestamp}`,
            balance: 50000000000,
            endTimestamp: 7797601500, // 90 days for the minimum operator stake
            startTimestamp: leavingTimestamp,
          },
          {
            vaultId: 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
            cursorId: `mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm_${leavingTimestamp}`,
            balance: 50000000000,
            endTimestamp: 2613601500, // 30 days for the remaining stake
            startTimestamp: leavingTimestamp,
          },
        ],
      );
    });
  });

  describe('Update-Gateway-Settings', () => {
    async function updateGatewaySettingsTest({
      settingsTags,
      expectedUpdatedGatewayProps = {},
      expectedUpdatedSettings,
      delegateAddresses,
      expectedDelegates,
      expectedAllowedDelegates,
      inputMemory = sharedMemory,
    }) {
      // gateway before
      const gateway = await getGateway({
        address: STUB_ADDRESS,
        memory: inputMemory,
      });

      const { memory: updatedSettingsMemory } = await updateGatewaySettings({
        memory: inputMemory,
        address: STUB_ADDRESS,
        settingsTags: [
          { name: 'Action', value: 'Update-Gateway-Settings' },
          ...settingsTags,
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
        ...expectedUpdatedGatewayProps,
        settings: {
          ...gateway.settings,
          ...expectedUpdatedSettings,
        },
      });

      var nextMemory = updatedSettingsMemory;
      if (delegateAddresses && expectedDelegates) {
        for (const delegateAddress of delegateAddresses) {
          const maybeDelegateResult = await delegateStake({
            memory: nextMemory,
            timestamp: STUB_TIMESTAMP,
            delegatorAddress: delegateAddress,
            quantity: 500_000_000,
            gatewayAddress: STUB_ADDRESS,
          }).catch(() => {});
          if (maybeDelegateResult?.memory) {
            nextMemory = maybeDelegateResult.memory;
          }
        }
        const updatedGatewayDelegates = await getDelegatesItems({
          memory: nextMemory,
          gatewayAddress: STUB_ADDRESS,
        });
        assert.deepEqual(
          updatedGatewayDelegates
            .map((delegateItem) => delegateItem.address)
            .sort(),
          expectedDelegates.slice().sort(),
        );
        const updatedAllowedDelegates = await getAllowedDelegatesItems({
          memory: nextMemory,
          gatewayAddress: STUB_ADDRESS,
        });
        assert.deepEqual(
          updatedAllowedDelegates.sort(),
          (expectedAllowedDelegates?.slice() || []).sort(),
        );
        for (const delegateAddress of expectedDelegates) {
          const allowlistingExpectedActive =
            (expectedAllowedDelegates?.length || 0) > 0;
          const delegateExpectedAllowed =
            expectedAllowedDelegates?.includes(delegateAddress) || false;
          const delegateHasBalance =
            ((updatedGatewayDelegates || []).filter(
              (item) => item.address === delegateAddress,
            )?.[0]?.delegatedStake || 0) > 0;
          assert(
            !allowlistingExpectedActive ||
              delegateExpectedAllowed === delegateHasBalance,
          );
        }
      }

      return nextMemory;
    }

    it('should allow updating the gateway settings', async () => {
      await updateGatewaySettingsTest({
        settingsTags: [
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
        expectedUpdatedSettings: {
          label: 'new-label',
          note: 'new-note',
          fqdn: 'new-fqdn',
          port: 80,
          protocol: 'https',
          allowDelegatedStaking: false,
          minDelegatedStake: 1_000_000_000,
          delegateRewardShareRatio: 10,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          autoStake: false,
        },
        delegateAddresses: [STUB_ADDRESS_9],
        expectedDelegates: [],
      });
    });

    it('should ignore Allowed-Delegates when allowlist is not active before or after the update', async () => {
      const updateMemory = await updateGatewaySettingsTest({
        settingsTags: [{ name: 'Allowed-Delegates', value: STUB_ADDRESS_9 }],
        expectedUpdatedSettings: {},
        delegateAddresses: [STUB_ADDRESS_9, STUB_ADDRESS_8],
        expectedDelegates: [STUB_ADDRESS_9, STUB_ADDRESS_8],
        expectedAllowedDelegates: [], // the settings update was ignored
      });

      await updateGatewaySettingsTest({
        inputMemory: updateMemory,
        settingsTags: [{ name: 'Allowed-Delegates', value: STUB_ADDRESS_9 }],
        expectedUpdatedSettings: {},
        expectedDelegates: [STUB_ADDRESS_9, STUB_ADDRESS_8], // Previous delegates NOT kicked
        expectedAllowedDelegates: [STUB_ADDRESS_9], // probs empty
      });

      await updateGatewaySettingsTest({
        settingsTags: [
          { name: 'Allow-Delegated-Staking', value: 'false' },
          { name: 'Allowed-Delegates', value: STUB_ADDRESS_9 },
        ],
        expectedUpdatedSettings: {
          allowDelegatedStaking: false,
        },
        delegateAddresses: [STUB_ADDRESS_9, STUB_ADDRESS_8],
        expectedDelegates: [], // No on can delegate
        expectedAllowedDelegates: [],
      });
    });

    it('should apply Allowed-Delegates when allowlist made active', async () => {
      const { memory: stakedMemory } = await delegateStake({
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP,
        delegatorAddress: STUB_ADDRESS_8,
        quantity: 500_000_000,
        gatewayAddress: STUB_ADDRESS,
      });
      const updatedMemory = await updateGatewaySettingsTest({
        inputMemory: stakedMemory,
        settingsTags: [
          { name: 'Allow-Delegated-Staking', value: 'allowlist' },
          {
            name: 'Allowed-Delegates',
            value: [STUB_ADDRESS_9, STUB_ADDRESS_7].join(','),
          },
        ],
        expectedUpdatedGatewayProps: {
          totalDelegatedStake: 0, // 8 exiting and 9 not yet joined
        },
        expectedUpdatedSettings: {
          allowDelegatedStaking: true,
        },
        delegateAddresses: [STUB_ADDRESS_9, STUB_ADDRESS_7, STUB_ADDRESS_6], // 6 is not allowed to delegate
        expectedDelegates: [STUB_ADDRESS_9, STUB_ADDRESS_7, STUB_ADDRESS_8], // 8 is exiting
        expectedAllowedDelegates: [STUB_ADDRESS_9, STUB_ADDRESS_7],
      });

      const { Memory: _, ...delegationsResult } = await handle(
        {
          From: STUB_ADDRESS_8,
          Owner: STUB_ADDRESS_8,
          Tags: [
            { name: 'Action', value: 'Paginated-Delegations' },
            { name: 'Limit', value: '100' },
            { name: 'Sort-Order', value: 'desc' },
            { name: 'Sort-By', value: 'startTimestamp' },
          ],
        },
        updatedMemory,
      );
      assertNoResultError(delegationsResult);
      assert.deepEqual(
        [
          {
            // Kicked out due to not being in allowlist
            type: 'stake',
            gatewayAddress: STUB_ADDRESS,
            delegationId: `${STUB_ADDRESS}_${STUB_TIMESTAMP}`,
            balance: 0,
            startTimestamp: STUB_TIMESTAMP,
          },
          {
            type: 'vault',
            gatewayAddress: STUB_ADDRESS,
            delegationId: `${STUB_ADDRESS}_${STUB_TIMESTAMP}`,
            vaultId: 'mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm',
            balance: 500_000_000,
            endTimestamp: 2613600000,
            startTimestamp: STUB_TIMESTAMP,
          },
        ],
        JSON.parse(delegationsResult.Messages[0].Data).items,
      );

      await updateGatewaySettingsTest({
        inputMemory: updatedMemory,
        settingsTags: [{ name: 'Allow-Delegated-Staking', value: 'false' }],
        expectedUpdatedGatewayProps: {
          totalDelegatedStake: 0,
        },
        expectedUpdatedSettings: {
          allowDelegatedStaking: false,
        },
        delegateAddresses: [STUB_ADDRESS_6], // not allowed to delegate
        expectedDelegates: [STUB_ADDRESS_7, STUB_ADDRESS_8, STUB_ADDRESS_9], // Leftover from previous test and being forced to exit
        expectedAllowedDelegates: [],
      });
    });

    it('should allow applying an allowlist when Allowed-Delegates is not supplied', async () => {
      const { memory: stakedMemory } = await delegateStake({
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP,
        delegatorAddress: STUB_ADDRESS_8,
        quantity: 500_000_000,
        gatewayAddress: STUB_ADDRESS,
      });

      const updatedMemory = await updateGatewaySettingsTest({
        inputMemory: stakedMemory,
        settingsTags: [{ name: 'Allow-Delegated-Staking', value: 'allowlist' }],
        expectedUpdatedGatewayProps: {
          totalDelegatedStake: 0, // 8 kicked
        },
        expectedUpdatedSettings: {},
        delegateAddresses: [STUB_ADDRESS_9], // no one is allowed yet
        expectedDelegates: [STUB_ADDRESS_8], // 8 is exiting
        expectedAllowedDelegates: [],
      });

      const delegateItems = await getDelegatesItems({
        memory: updatedMemory,
        gatewayAddress: STUB_ADDRESS,
      });
      assert.deepEqual(
        [
          {
            startTimestamp: STUB_TIMESTAMP,
            delegatedStake: 0,
            vaults: {
              mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm: {
                balance: 500000000,
                startTimestamp: STUB_TIMESTAMP,
                endTimestamp: 2613600000,
              },
            },
            address: STUB_ADDRESS_8,
          },
        ],
        delegateItems,
      );

      const { result: getAllowedDelegatesResult } = await getAllowedDelegates({
        memory: updatedMemory,
        from: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP,
        gatewayAddress: STUB_ADDRESS,
      });
      assert.deepEqual(
        JSON.parse(getAllowedDelegatesResult.Messages?.[0]?.Data),
        {
          limit: 100,
          totalItems: 0,
          hasMore: false,
          items: [],
          sortOrder: 'desc',
        },
      );
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
      });
      assert.deepEqual(
        await getGatewayVaultsItems({
          memory: decreaseStakeMemory,
          gatewayAddress: STUB_ADDRESS,
        }),
        [
          {
            vaultId: decreaseMessageId,
            cursorId: `${decreaseMessageId}_${decreaseTimestamp}`,
            balance: decreaseQty,
            startTimestamp: decreaseTimestamp,
            endTimestamp: decreaseTimestamp + 1000 * 60 * 60 * 24 * 30, // should be 30 days for anything above the minimum
          },
        ],
      );
    });

    it('should not allow decreasing the operator stake if below the minimum withdrawal', async () => {
      const decreaseQty = 999_999;
      const decreaseTimestamp = STUB_TIMESTAMP + 1500;
      const decreaseMessageId = 'decrease-operator-stake-message-'.padEnd(
        43,
        '2',
      );
      const { result } = await decreaseOperatorStake({
        address: STUB_ADDRESS,
        timestamp: decreaseTimestamp,
        memory: sharedMemory,
        messageId: decreaseMessageId,
        decreaseQty,
        assert: false,
      });

      const error = result.Error;
      assert.ok(error, 'Error tag should be present');
      assert(
        error.includes(
          'Invalid quantity. Must be integer greater than 1000000',
        ),
      );
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
      });
      assert.deepEqual(
        await getGatewayVaultsItems({
          memory: decreaseInstantMemory,
          gatewayAddress: STUB_ADDRESS,
        }),
        [],
      );

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
      });
      const delegateItems = await getDelegatesItems({
        memory: delegatedStakeMemory,
        gatewayAddress: STUB_ADDRESS,
      });
      assert.deepEqual(
        [
          {
            startTimestamp: delegationTimestamp,
            delegatedStake: delegatedQty,
            vaults: [],
            address: delegatorAddress,
          },
        ],
        delegateItems,
      );
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
      });
      const delegateItems = await getDelegatesItems({
        memory: decreaseStakeMemory,
        gatewayAddress: STUB_ADDRESS,
      });
      assert.deepEqual(
        [
          {
            startTimestamp: STUB_TIMESTAMP,
            delegatedStake: stakeQty - decreaseQty,
            vaults: {
              [decreaseStakeMsgId]: {
                balance: decreaseQty,
                startTimestamp: decreaseStakeTimestamp,
                endTimestamp: decreaseStakeTimestamp + 1000 * 60 * 60 * 24 * 30,
              },
            },
            address: delegatorAddress,
          },
        ],
        delegateItems,
      );
    });

    it('should fail to withdraw a delegated stake if below the minimum withdrawal limitation', async () => {
      const decreaseStakeTimestamp = STUB_TIMESTAMP + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const stakeQty = 10000000000;
      const decreaseQty = 999_999; // below the minimum withdrawal limitation of 1_000_000
      const decreaseStakeMsgId = 'decrease-stake-message-id-'.padEnd(43, 'x');
      const { memory: delegatedStakeMemory } = await delegateStake({
        delegatorAddress,
        quantity: stakeQty,
        gatewayAddress: STUB_ADDRESS,
        timestamp: STUB_TIMESTAMP,
        memory: sharedMemory,
        assert: false,
      });

      const gatewayBefore = await getGateway({
        address: STUB_ADDRESS,
        memory: delegatedStakeMemory,
      });
      const { memory: decreaseStakeMemory, result } =
        await decreaseDelegateStake({
          memory: delegatedStakeMemory,
          delegatorAddress,
          decreaseQty,
          timestamp: decreaseStakeTimestamp,
          gatewayAddress: STUB_ADDRESS,
          messageId: decreaseStakeMsgId,
          assert: false,
        });

      assert.ok(result.Error, 'Error tag should be present');
      assert(
        result.Error.includes(
          'Invalid quantity. Must be integer greater than 1000000',
        ),
      );
      // get the gateway record
      const gatewayAfter = await getGateway({
        address: STUB_ADDRESS,
        memory: decreaseStakeMemory,
      });
      assert.deepStrictEqual(gatewayAfter, gatewayBefore);
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
      });
      const getDelegatesResult = await getDelegatesItems({
        memory: instantWithdrawalMemory,
        gatewayAddress: STUB_ADDRESS,
      });
      assert.deepEqual(getDelegatesResult, []);

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

  describe('Paginated-Gateways', () => {
    it('should paginate gateways correctly', async () => {
      // add another gateway
      const secondGatewayAddress = 'second-gateway-'.padEnd(43, 'a');
      const { memory: addGatewayMemory2 } = await joinNetwork({
        address: secondGatewayAddress,
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP - 1,
      });
      let cursor;
      let fetchedGateways = [];
      while (true) {
        const paginatedGateways = await handle(
          {
            Tags: [
              { name: 'Action', value: 'Paginated-Gateways' },
              { name: 'Cursor', value: cursor },
              { name: 'Limit', value: '1' },
            ],
          },
          addGatewayMemory2,
        );
        // parse items, nextCursor
        const { items, nextCursor, hasMore, sortBy, sortOrder, totalItems } =
          JSON.parse(paginatedGateways.Messages?.[0]?.Data);
        assert.equal(totalItems, 2);
        assert.equal(items.length, 1);
        assert.equal(sortBy, 'startTimestamp');
        assert.equal(sortOrder, 'desc');
        assert.equal(hasMore, !!nextCursor);
        cursor = nextCursor;
        fetchedGateways.push(...items);
        if (!cursor) break;
      }
      assert.deepEqual(
        fetchedGateways.map((g) => g.gatewayAddress),
        [STUB_ADDRESS, secondGatewayAddress],
      );
    });
  });

  // save observations
  describe('Save-Observations', () => {
    it('should save observations', async () => {
      // Steps: add a gateway, create the first epoch to prescribe it, submit an observation from the gateway, tick to the epoch distribution timestamp, check the rewards were distributed correctly
    });
  });

  describe('Paginated-Delegations', () => {
    async function testPaginatedDelegations({
      sortBy,
      sortOrder,
      expectedDelegations,
    }) {
      const userAddress = 'user-address-'.padEnd(43, 'a');

      // add another gateway
      const secondGatewayAddress = 'second-gateway-'.padEnd(43, 'a');
      const { memory: addGatewayMemory2 } = await joinNetwork({
        address: secondGatewayAddress,
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP - 1,
      });

      // Stake to both gateways
      const { memory: stakedMemory } = await delegateStake({
        memory: addGatewayMemory2,
        timestamp: STUB_TIMESTAMP,
        delegatorAddress: userAddress,
        quantity: 1_000_000_000,
        gatewayAddress: STUB_ADDRESS,
      });
      const { memory: stakedMemory2 } = await delegateStake({
        memory: stakedMemory,
        timestamp: STUB_TIMESTAMP + 1,
        delegatorAddress: userAddress,
        quantity: 600_000_000,
        gatewayAddress: secondGatewayAddress,
      });

      // Decrease stake on first gateway to create a vault
      const decreaseQty = 400_000_001;
      const { memory: decreaseStakeMemory } = await decreaseDelegateStake({
        memory: stakedMemory2,
        timestamp: STUB_TIMESTAMP + 2,
        delegatorAddress: userAddress,
        decreaseQty,
        gatewayAddress: STUB_ADDRESS,
        messageId: 'decrease-stake-message-id',
      });

      let cursor;
      let fetchedDelegations = [];
      while (true) {
        const paginatedDelegations = await handle(
          {
            From: userAddress,
            Owner: userAddress,
            Tags: [
              { name: 'Action', value: 'Paginated-Delegations' },
              { name: 'Limit', value: '1' },
              { name: 'Sort-By', value: sortBy },
              { name: 'Sort-Order', value: sortOrder },
              ...(cursor ? [{ name: 'Cursor', value: `${cursor}` }] : []),
            ],
          },
          decreaseStakeMemory,
        );
        const { items, nextCursor, hasMore, totalItems } = JSON.parse(
          paginatedDelegations.Messages?.[0]?.Data,
        );
        assert.equal(totalItems, 3);
        assert.equal(items.length, 1);
        assert.equal(hasMore, !!nextCursor);
        cursor = nextCursor;
        fetchedDelegations.push(...items);
        if (!cursor) break;
      }
      assert.deepEqual(fetchedDelegations, expectedDelegations);
    }

    it('should paginate active and vaulted stakes by ascending balance correctly', async () => {
      await testPaginatedDelegations({
        sortBy: 'balance',
        sortOrder: 'asc',
        expectedDelegations: [
          {
            type: 'vault',
            gatewayAddress: '2222222222222222222222222222222222222222222',
            startTimestamp: 21600002,
            delegationId:
              '2222222222222222222222222222222222222222222_21600002',
            balance: 400000001,
            vaultId: 'decrease-stake-message-id',
            endTimestamp: 2613600002,
          },
          {
            type: 'stake',
            gatewayAddress: '2222222222222222222222222222222222222222222',
            delegationId:
              '2222222222222222222222222222222222222222222_21600000',
            balance: 599999999,
            startTimestamp: 21600000,
          },
          {
            type: 'stake',
            gatewayAddress: 'second-gateway-aaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            delegationId:
              'second-gateway-aaaaaaaaaaaaaaaaaaaaaaaaaaaa_21600001',
            balance: 600000000,
            startTimestamp: 21600001,
          },
        ],
      });
    });

    it('should paginate active and vaulted stakes by descending timestamp correctly', async () => {
      await testPaginatedDelegations({
        sortBy: 'startTimestamp',
        sortOrder: 'desc',
        expectedDelegations: [
          {
            type: 'vault',
            gatewayAddress: '2222222222222222222222222222222222222222222',
            startTimestamp: 21600002,
            delegationId:
              '2222222222222222222222222222222222222222222_21600002',
            balance: 400000001,
            vaultId: 'decrease-stake-message-id',
            endTimestamp: 2613600002,
          },
          {
            type: 'stake',
            gatewayAddress: 'second-gateway-aaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            delegationId:
              'second-gateway-aaaaaaaaaaaaaaaaaaaaaaaaaaaa_21600001',
            balance: 600000000,
            startTimestamp: 21600001,
          },
          {
            type: 'stake',
            gatewayAddress: '2222222222222222222222222222222222222222222',
            delegationId:
              '2222222222222222222222222222222222222222222_21600000',
            balance: 599999999,
            startTimestamp: 21600000,
          },
        ],
      });
    });
  });

  describe('Redelegate-Stake', () => {
    const redelegateStake = async ({
      memory,
      delegatorAddress,
      quantity,
      sourceAddress,
      targetAddress,
      vaultId,
      timestamp,
    }) => {
      const result = await handle(
        {
          From: delegatorAddress,
          Owner: delegatorAddress,
          Tags: [
            { name: 'Action', value: 'Redelegate-Stake' },
            { name: 'Source', value: sourceAddress },
            { name: 'Target', value: targetAddress },
            { name: 'Quantity', value: `${quantity}` },
            ...(vaultId ? [{ name: 'Vault-Id', value: vaultId }] : []),
          ],
          Timestamp: timestamp,
        },
        memory,
      );
      return {
        result,
        memory: result.Memory,
      };
    };

    const sourceAddress = 'source-address-'.padEnd(43, 'a');
    const targetAddress = 'target-address-'.padEnd(43, 'b');
    const delegatorAddress = 'delegator-address-'.padEnd(43, 'c');
    const stakeQty = 500_000_000;

    it('should allow re-delegating stake', async () => {
      const { memory: joinSourceMemory } = await joinNetwork({
        address: sourceAddress,
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP,
      });
      const { memory: joinTargetMemory } = await joinNetwork({
        address: targetAddress,
        memory: joinSourceMemory,
        timestamp: STUB_TIMESTAMP,
      });
      const transferMemory = await transfer({
        recipient: delegatorAddress,
        quantity: stakeQty,
        memory: joinTargetMemory,
      });

      const { memory: delegatedStakeMemory } = await delegateStake({
        delegatorAddress,
        quantity: stakeQty,
        gatewayAddress: sourceAddress,
        timestamp: STUB_TIMESTAMP,
        memory: transferMemory,
      });

      const sourceGatewayBefore = await getGateway({
        address: sourceAddress,
        memory: delegatedStakeMemory,
      });
      assert(sourceGatewayBefore.totalDelegatedStake === stakeQty);
      const delegateItems = await getDelegatesItems({
        memory: delegatedStakeMemory,
        gatewayAddress: sourceAddress,
      });
      assert.deepEqual(
        [
          {
            startTimestamp: STUB_TIMESTAMP,
            delegatedStake: stakeQty,
            vaults: [],
            address: delegatorAddress,
          },
        ],
        delegateItems,
      );

      const { memory: redelegateStakeMemory, result } = await redelegateStake({
        memory: delegatedStakeMemory,
        delegatorAddress,
        quantity: stakeQty,
        sourceAddress,
        targetAddress,
        timestamp: STUB_TIMESTAMP,
      });

      const targetGatewayAfter = await getGateway({
        address: targetAddress,
        memory: redelegateStakeMemory,
        timestamp: STUB_TIMESTAMP,
      });
      assert(targetGatewayAfter.totalDelegatedStake === stakeQty);
      assert.deepEqual(
        await getDelegatesItems({
          memory: redelegateStakeMemory,
          gatewayAddress: targetAddress,
        }),
        [
          {
            delegatedStake: stakeQty,
            startTimestamp: STUB_TIMESTAMP,
            vaults: [],
            address: delegatorAddress,
          },
        ],
      );

      const sourceGatewayAfter = await getGateway({
        address: sourceAddress,
        memory: redelegateStakeMemory,
        timestamp: STUB_TIMESTAMP,
      });
      assert(sourceGatewayAfter.totalDelegatedStake === 0);
      assert.deepEqual(
        await getDelegatesItems({
          memory: redelegateStakeMemory,
          gatewayAddress: sourceAddress,
        }),
        [],
      );

      const feeResultAfterRedelegation = await handle(
        {
          From: delegatorAddress,
          Owner: delegatorAddress,
          Tags: [{ name: 'Action', value: 'Redelegation-Fee' }],
          Timestamp: STUB_TIMESTAMP,
        },
        redelegateStakeMemory,
      );
      assert.deepStrictEqual(
        JSON.parse(feeResultAfterRedelegation.Messages[0].Data),
        {
          redelegationFeeRate: 10,
          feeResetTimestamp: STUB_TIMESTAMP + 1000 * 60 * 60 * 24 * 7, // 7 days
        },
      );

      // Fee is pruned after 7 days
      const feeResultSevenEpochsLater = await handle(
        {
          From: delegatorAddress,
          Owner: delegatorAddress,
          Tags: [{ name: 'Action', value: 'Redelegation-Fee' }],
          Timestamp: STUB_TIMESTAMP + 1000 * 60 * 60 * 24 * 7 * 7 + 1, // 7 days
        },
        redelegateStakeMemory,
      );
      assert.deepStrictEqual(
        JSON.parse(feeResultSevenEpochsLater.Messages[0].Data),
        {
          redelegationFeeRate: 0,
        },
      );
    });

    it("should allow re-delegating stake with a vault and the vault's balance", async () => {
      const { memory: joinSourceMemory } = await joinNetwork({
        address: sourceAddress,
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP,
      });
      const { memory: joinTargetMemory } = await joinNetwork({
        address: targetAddress,
        memory: joinSourceMemory,
        timestamp: STUB_TIMESTAMP,
      });
      const transferMemory = await transfer({
        recipient: delegatorAddress,
        quantity: stakeQty,
        memory: joinTargetMemory,
      });

      const { memory: delegatedStakeMemory } = await delegateStake({
        delegatorAddress,
        quantity: stakeQty,
        gatewayAddress: sourceAddress,
        timestamp: STUB_TIMESTAMP,
        memory: transferMemory,
      });

      const sourceGatewayBefore = await getGateway({
        address: sourceAddress,
        memory: delegatedStakeMemory,
      });
      assert(sourceGatewayBefore.totalDelegatedStake === stakeQty);
      const delegateItems = await getDelegatesItems({
        memory: delegatedStakeMemory,
        gatewayAddress: sourceAddress,
      });
      assert.deepStrictEqual(
        [
          {
            startTimestamp: STUB_TIMESTAMP,
            delegatedStake: stakeQty,
            vaults: [],
            address: delegatorAddress,
          },
        ],
        delegateItems,
      );

      const decreaseStakeMsgId = 'decrease-stake-message-id-'.padEnd(43, 'x');
      const { memory: decreaseStakeMemory } = await decreaseDelegateStake({
        memory: delegatedStakeMemory,
        timestamp: STUB_TIMESTAMP + 1,
        delegatorAddress,
        decreaseQty: stakeQty,
        gatewayAddress: sourceAddress,
        messageId: decreaseStakeMsgId,
      });

      const { memory: redelegateStakeMemory } = await redelegateStake({
        memory: decreaseStakeMemory,
        delegatorAddress,
        quantity: stakeQty,
        sourceAddress,
        targetAddress,
        vaultId: decreaseStakeMsgId,
        timestamp: STUB_TIMESTAMP + 2,
      });

      const targetGatewayAfter = await getGateway({
        address: targetAddress,
        memory: redelegateStakeMemory,
        timestamp: STUB_TIMESTAMP + 2,
      });
      assert(targetGatewayAfter.totalDelegatedStake === stakeQty);
      assert.deepStrictEqual(
        await getDelegatesItems({
          memory: redelegateStakeMemory,
          gatewayAddress: targetAddress,
        }),
        [
          {
            delegatedStake: stakeQty,
            startTimestamp: STUB_TIMESTAMP + 2,
            address: delegatorAddress,
            vaults: [],
          },
        ],
      );

      const sourceGatewayAfter = await getGateway({
        address: sourceAddress,
        memory: redelegateStakeMemory,
        timestamp: STUB_TIMESTAMP + 2,
      });
      assert(sourceGatewayAfter.totalDelegatedStake === 0);
      assert.deepStrictEqual(
        await getDelegatesItems({
          memory: redelegateStakeMemory,
          gatewayAddress: sourceAddress,
        }),
        [],
      );
    });
  });
});
