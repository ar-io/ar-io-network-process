import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import {
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  PROCESS_ID,
  STUB_TIMESTAMP,
  INITIAL_OPERATOR_STAKE,
  INITIAL_DELEGATE_STAKE,
  STUB_HASH_CHAIN,
} from '../tools/constants.mjs';
import {
  getBaseRegistrationFeeForName,
  getDemandFactor,
  getDelegatesItems,
  delegateStake,
  getGateway,
  joinNetwork,
  buyRecord,
  handle,
  transfer,
  startMemory,
  returnedNamesPeriod,
  totalTokenSupply,
  getEpoch,
  tick,
  saveObservations,
  getEpochSettings,
  leaveNetwork,
  getDemandFactorSettings,
} from './helpers.mjs';
import { assertNoInvariants } from './invariants.mjs';

describe('Tick', async () => {
  let sharedMemory;
  let epochSettings;
  let lastTimestamp;
  beforeEach(async () => {
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    epochSettings = await getEpochSettings({
      memory: startMemory,
    });
    sharedMemory = totalTokenSupplyMemory;
  });

  afterEach(async () => {
    await assertNoInvariants({
      timestamp: lastTimestamp,
      memory: sharedMemory,
    });
  });

  it('should prune record that are expired and after the grace period and create returned names for them', async () => {
    const memory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 100_000_000_000,
      memory: sharedMemory,
    });
    const buyRecordResult = await buyRecord({
      memory,
      name: 'test-name',
      type: 'lease',
      from: STUB_ADDRESS,
      processId: ''.padEnd(43, 'a'),
    });
    const realRecord = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      memory: buyRecordResult.memory,
    });
    const buyRecordData = JSON.parse(realRecord.Messages[0].Data);
    assert.deepEqual(buyRecordData, {
      processId: ''.padEnd(43, 'a'),
      purchasePrice: 600000000,
      type: 'lease',
      undernameLimit: 10,
      startTimestamp: buyRecordData.startTimestamp,
      endTimestamp: buyRecordData.endTimestamp,
    });

    // mock the passage of time and tick with a future timestamp
    const futureTimestamp =
      buyRecordData.endTimestamp + 1000 * 60 * 60 * 24 * 14 + 1;
    const { result: futureTickResult } = await tick({
      memory: buyRecordResult.memory,
      timestamp: futureTimestamp,
    });

    const tickEvent = JSON.parse(
      futureTickResult.Output.data
        .split('\n')
        .filter((line) => line.includes('_e'))[0],
    );
    assert.equal(tickEvent['Records-Count'], 0);
    assert.equal(tickEvent['Pruned-Records-Count'], 1);
    assert.deepEqual(tickEvent['Pruned-Records'], ['test-name']);

    // the record should be pruned
    const prunedRecord = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
        Timestamp: futureTimestamp,
      },
      memory: futureTickResult.Memory,
    });

    const prunedRecordData = JSON.parse(prunedRecord.Messages[0].Data);

    assert.deepEqual(undefined, prunedRecordData);

    // the returnedName should have been created
    const returnedNameData = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Returned-Name' },
          { name: 'Name', value: 'test-name' },
        ],
        Timestamp: futureTimestamp,
      },

      memory: futureTickResult.Memory,
    });
    const returnedNameInfoData = JSON.parse(returnedNameData.Messages[0].Data);
    assert.deepEqual(returnedNameInfoData, {
      name: 'test-name',
      startTimestamp: futureTimestamp,
      endTimestamp: futureTimestamp + returnedNamesPeriod,
      initiator: PROCESS_ID,
      premiumMultiplier: 50,
    });
    sharedMemory = returnedNameData.Memory;
  });

  it('should prune gateways that are expired', async () => {
    const memory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 100_000_000_000,
      memory: sharedMemory,
    });
    const joinNetworkResult = await joinNetwork({
      memory,
      address: STUB_ADDRESS,
    });

    // check the gateway record from contract
    const gateway = await getGateway({
      memory: joinNetworkResult.memory,
      address: STUB_ADDRESS,
    });
    assert.deepEqual(gateway.status, 'joined');

    // leave the network
    const leaveNetworkResult = await leaveNetwork({
      memory: joinNetworkResult.memory,
      address: STUB_ADDRESS,
    });

    // check the gateways status is leaving
    const leavingGateway = await getGateway({
      memory: leaveNetworkResult.memory,
      address: STUB_ADDRESS,
    });
    assert.deepEqual(leavingGateway.status, 'leaving');
    // TODO: check delegates and operator stake are vaulted

    // expedite the timestamp to the future
    const futureTimestamp = leavingGateway.endTimestamp + 1;
    const futureTick = await tick({
      memory: leaveNetworkResult.memory,
      timestamp: futureTimestamp,
    });

    // check the gateway is pruned
    const prunedGateway = await getGateway({
      memory: futureTick.memory,
      address: STUB_ADDRESS,
      timestamp: futureTimestamp,
    });

    assert.deepEqual(undefined, prunedGateway);
    sharedMemory = futureTick.memory;
    lastTimestamp = futureTimestamp;
  });

  // vaulting is not working as expected, need to fix before enabling this test
  it('should prune vaults that are expired', async () => {
    const lockLengthMs = 1209600000;
    const quantity = 1000000000;
    const balanceBefore = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Balance' }],
      },
      memory: sharedMemory,
    });
    const balanceBeforeData = JSON.parse(balanceBefore.Messages[0].Data);
    const createVaultResult = await handle({
      options: {
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
            value: lockLengthMs.toString(), // the minimum lock length is 14 days
          },
        ],
      },
      memory: sharedMemory,
    });
    // parse the data and ensure the vault was created
    const createVaultResultData = JSON.parse(
      createVaultResult.Messages[0].Data,
    );
    const vaultId = createVaultResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Vault-Id',
    ).value;
    // assert the vault id is in the tags
    assert.deepEqual(vaultId, DEFAULT_HANDLE_OPTIONS.Id);

    // assert the balance is deducted
    const balanceAfterVault = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Balance' }],
      },
      memory: createVaultResult.Memory,
    });
    const balanceAfterVaultData = JSON.parse(
      balanceAfterVault.Messages[0].Data,
    );
    assert.deepEqual(balanceAfterVaultData, balanceBeforeData - quantity);

    // check that vault exists
    const vault = await handle({
      options: {
        Tags: [
          {
            name: 'Action',
            value: 'Vault',
          },
          {
            name: 'Vault-Id',
            value: vaultId,
          },
        ],
      },
      memory: createVaultResult.Memory,
    });
    const vaultData = JSON.parse(vault.Messages[0].Data);
    assert.deepEqual(
      createVaultResultData.balance,
      vaultData.balance,
      quantity,
    );
    assert.deepEqual(
      vaultData.startTimestamp,
      createVaultResultData.startTimestamp,
    );
    assert.deepEqual(
      vaultData.endTimestamp,
      createVaultResultData.endTimestamp,
      createVaultResult.startTimestamp + lockLengthMs,
    );
    // mock the passage of time and tick with a future timestamp
    const futureTimestamp = vaultData.endTimestamp + 1;
    const futureTick = await tick({
      memory: createVaultResult.Memory,
      timestamp: futureTimestamp,
    });

    // check the vault is pruned
    const prunedVault = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Vault' }],
        Timestamp: futureTimestamp,
      },
      memory: futureTick.Memory,
      shouldAssertNoResultError: false,
    });
    // it should have an error tag
    assert.ok(
      prunedVault.Messages[0].Tags.find((tag) => tag.name === 'Error'),
      'Error tag should be present',
    );

    // Check that the balance is returned to the owner
    const ownerBalance = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Balance' },
          { name: 'Target', value: DEFAULT_HANDLE_OPTIONS.Owner },
        ],
        Timestamp: futureTimestamp,
      },
      memory: futureTick.Memory,
    });
    const balanceData = JSON.parse(ownerBalance.Messages[0].Data);
    assert.equal(balanceData, balanceBeforeData);
    sharedMemory = ownerBalance.Memory;
    lastTimestamp = futureTimestamp;
  });

  /**
   * Summary:
   * - give balance to gateway
   * - join the network
   * - give balance to delegate
   * - delegate to the gateway
   * - tick to create the first epoch
   * - validate the epoch is created correctly
   * - submit an observation from the gateway prescribed
   * - tick to the epoch distribution timestamp
   * - validate the rewards were distributed correctly
   * - send epoch distribution notice containing full epoch data
   */
  it('should distribute rewards to gateways and delegates, send an epoch distribution notice and remove the epoch from the epoch registry', async () => {
    // give balance to gateway
    const initialMemory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 100_000_000_000,
      memory: sharedMemory,
    });

    const delegateAddress = 'delegate-address-'.padEnd(43, '1');
    // add the gateway
    const joinNetworkTimestamp =
      epochSettings.epochZeroStartTimestamp - epochSettings.durationMs * 180; // 180 epochs (6-months) before the first epoch
    const { result: newGateway } = await joinNetwork({
      memory: initialMemory,
      address: STUB_ADDRESS,
      timestamp: joinNetworkTimestamp,
    });

    // give balance to delegate and stake - making the gateway weight 3 * the minimum
    const delegateQuantity = INITIAL_OPERATOR_STAKE * 2;
    const delegateTimestamp =
      epochSettings.epochZeroStartTimestamp - epochSettings.durationMs * 15; // 15 epochs before the first epoch
    const transferMemory = await transfer({
      recipient: delegateAddress,
      quantity: delegateQuantity,
      memory: newGateway.Memory,
      timestamp: delegateTimestamp,
    });
    const { result: newDelegateResult } = await delegateStake({
      gatewayAddress: STUB_ADDRESS,
      delegatorAddress: delegateAddress,
      quantity: delegateQuantity,
      timestamp: delegateTimestamp,
      memory: transferMemory,
    });

    const { result: newEpochTick, memory: newEpochTickMemory } = await tick({
      memory: newDelegateResult.Memory,
      timestamp: epochSettings.epochZeroStartTimestamp,
      forcePrune: true,
      hashchain: 'hashchain-'.padEnd(43, '1'),
    });

    // should only have one message with a tick notice, the epoch distribution notice is sent separately
    assert.equal(newEpochTick.Messages.length, 2);
    assert.equal(
      newEpochTick.Messages[0].Tags.find((tag) => tag.name === 'Action').value,
      'Epoch-Created-Notice',
    );
    assert.equal(
      newEpochTick.Messages[1].Tags.find((tag) => tag.name === 'Action').value,
      'Tick-Notice',
    );

    const createdEpochData = JSON.parse(newEpochTick.Messages[0].Data);

    // assert the new epoch is created
    const epochData = await getEpoch({
      memory: newEpochTickMemory,
      timestamp: epochSettings.epochZeroStartTimestamp,
    });

    // get the epoch timestamp and assert it is in 24 hours
    const protocolBalanceAtStartOfEpoch = 50_000_000_000_000; // 50M ARIO
    const totalEligibleRewards = protocolBalanceAtStartOfEpoch * 0.0005; // 0.05% of the protocol balance
    const totalGatewayRewards = Math.ceil(totalEligibleRewards * 0.9); // 90% go to gateways
    const totalObserverRewards = Math.floor(totalEligibleRewards * 0.1); // 10% go to observers
    const totalEligibleGatewayRewards =
      (totalGatewayRewards + totalObserverRewards) / 1; // only one gateway in the network
    const expectedGatewayOperatorReward = totalEligibleGatewayRewards * 0.75; // 75% of the eligible rewards go to the operator
    const expectedGatewayDelegateReward = totalEligibleGatewayRewards * 0.25; // 25% of the eligible rewards go to the delegates

    // assert the returned epoch data is an empty epoch with no prescribed observers
    assert.deepStrictEqual(epochData, {
      hashchain: 'hashchain-'.padEnd(43, '1'),
      epochIndex: 1,
      startHeight: 1,
      startTimestamp: epochSettings.epochZeroStartTimestamp,
      endTimestamp: epochSettings.epochZeroStartTimestamp + 24 * 1000 * 60 * 60, // 24 hours - this should match the epoch settings
      arnsStats: {
        totalActiveNames: 0,
        totalGracePeriodNames: 0,
        totalReservedNames: 0,
        totalReturnedNames: 0,
      },
      observations: {
        failureSummaries: [],
        reports: [],
      },
      prescribedNames: [], // no names in the network
      prescribedObservers: [
        {
          observerAddress: STUB_ADDRESS,
          gatewayAddress: STUB_ADDRESS,
          stake: INITIAL_OPERATOR_STAKE,
          stakeWeight: 3,
          compositeWeight: 3, // stake weight * tenure weight * observer performance ratio * gateway performance ratio
          gatewayPerformanceRatio: 1,
          observerPerformanceRatio: 1,
          normalizedCompositeWeight: 1,
          tenureWeight: 1, // epoch has been around for exactly 6 months, equivalent to 1 tenure period
          startTimestamp: joinNetworkTimestamp,
        },
      ],
      distributions: {
        totalEligibleGateways: 1,
        totalEligibleRewards: totalEligibleRewards,
        totalEligibleGatewayReward: totalGatewayRewards,
        totalEligibleObserverReward: totalObserverRewards,
        rewards: {
          eligible: {
            [STUB_ADDRESS]: {
              operatorReward: expectedGatewayOperatorReward,
              delegateRewards: {
                [delegateAddress]: expectedGatewayDelegateReward,
              },
            },
          },
        },
      },
    });

    // have the gateway submit an observation
    const reportTxId = 'report-tx-id-'.padEnd(43, '1');
    const observationTimestamp =
      epochSettings.epochZeroStartTimestamp + 7 * 1000 * 60 * 60; // 7 hours after the epoch is created
    const { memory: observationMemory } = await saveObservations({
      memory: newEpochTickMemory,
      timestamp: observationTimestamp,
      from: STUB_ADDRESS,
      reportTxId,
      epochIndex: 1,
    });

    // now jump ahead to the end of the epoch and tick
    const distributionTimestamp =
      epochSettings.epochZeroStartTimestamp + epochSettings.durationMs;
    const { memory: distributionMemory, result: distributionTick } = await tick(
      {
        memory: observationMemory,
        timestamp: distributionTimestamp,
      },
    );

    // assert multiple messages are sent given the tick notice, epoch created notice and epoch distribution notice
    assert.equal(distributionTick.Messages.length, 3); // 1 epoch distribution notice, 1 epoch created notice, 1 tick notice

    // new epoch is created
    const createdMessage = distributionTick.Messages.find(
      (m) =>
        m.Tags.find((t) => t.name === 'Action').value ===
        'Epoch-Created-Notice',
    );
    assert.ok(createdMessage, 'Epoch created notice should be sent');
    assert.equal(
      createdMessage.Tags.find((t) => t.name === 'Epoch-Index').value,
      '2',
    );

    // last epoch is distributed
    const distributionMessage = distributionTick.Messages.find(
      (m) =>
        m.Tags.find((t) => t.name === 'Action').value ===
        'Epoch-Distribution-Notice',
    );

    assert.ok(distributionMessage, 'Epoch distribution notice should be sent');
    assert.equal(
      distributionMessage.Tags.find((t) => t.name === 'Epoch-Index').value,
      '1',
    );

    // resulting tick notice is sent
    const tickMessage = distributionTick.Messages.find(
      (m) => m.Tags.find((t) => t.name === 'Action').value === 'Tick-Notice',
    );
    assert.ok(tickMessage, 'Tick notice should be sent');

    // assert the distribution notice has the correct data and is posted as a data item
    const distributionNoticeData = JSON.parse(distributionMessage.Data);
    assert.deepStrictEqual(distributionNoticeData, {
      ...epochData,
      distributions: {
        ...epochData.distributions,
        rewards: {
          ...epochData.distributions.rewards,
          distributed: {
            [STUB_ADDRESS]: expectedGatewayOperatorReward,
            [delegateAddress]: expectedGatewayDelegateReward,
          },
        },
        totalDistributedRewards: totalEligibleRewards,
        distributedTimestamp: distributionTimestamp,
      },
      observations: {
        failureSummaries: [],
        reports: {
          [STUB_ADDRESS]: reportTxId,
        },
      },
    });

    // assert the new epoch was created
    const newEpoch = await getEpoch({
      memory: distributionMemory,
      timestamp: distributionTimestamp,
    });
    assert.equal(newEpoch.epochIndex, 2);

    // assert the gateway stakes were updated and match the distributed rewards
    const gateway = await getGateway({
      memory: distributionMemory,
      address: STUB_ADDRESS,
      timestamp: distributionTimestamp,
    });

    assert.deepStrictEqual(gateway, {
      status: 'joined',
      startTimestamp: joinNetworkTimestamp,
      observerAddress: STUB_ADDRESS,
      operatorStake: INITIAL_OPERATOR_STAKE + expectedGatewayOperatorReward,
      totalDelegatedStake: delegateQuantity + expectedGatewayDelegateReward,
      settings: {
        allowDelegatedStaking: true,
        autoStake: true,
        delegateRewardShareRatio: 25,
        minDelegatedStake: INITIAL_DELEGATE_STAKE,
        fqdn: 'test-fqdn',
        label: 'test-gateway',
        note: 'test-note',
        port: 443,
        properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
        protocol: 'https',
      },
      stats: {
        failedConsecutiveEpochs: 0,
        failedEpochCount: 0,
        observedEpochCount: 1,
        passedEpochCount: 1,
        passedConsecutiveEpochs: 1,
        prescribedEpochCount: 1,
        totalEpochCount: 1,
      },
      weights: {
        compositeWeight: 5.530555555555555,
        gatewayPerformanceRatio: 1,
        normalizedCompositeWeight: 1,
        observerPerformanceRatio: 1,
        stakeWeight: 5.5,
        tenureWeight: 1.0055555555555555,
      },
    });

    const delegateItems = await getDelegatesItems({
      memory: distributionMemory,
      gatewayAddress: STUB_ADDRESS,
      timestamp: distributionTimestamp,
    });

    assert.deepEqual(delegateItems, [
      {
        delegatedStake: delegateQuantity + expectedGatewayDelegateReward,
        startTimestamp: delegateTimestamp,
        address: delegateAddress,
      },
    ]);

    // assert the distributed epoch was removed from the epoch registry
    const prunedEpoch = await getEpoch({
      memory: distributionMemory,
      timestamp: distributionTimestamp,
      epochIndex: 1,
    });
    assert.equal(prunedEpoch, undefined);
    sharedMemory = distributionMemory;
    lastTimestamp = distributionTimestamp;
  });

  it('should not increase demandFactor and baseRegistrationFee when records are bought until the end of the epoch', async () => {
    // NOTE: we are not using shared memory here as we want to validate the demandFactor and baseRegistrationFee are correct before any distributions have occurred
    const demandFactorSettings = await getDemandFactorSettings({
      memory: sharedMemory,
      timestamp: epochSettings.epochZeroStartTimestamp,
    });
    const firstDemandFactorPeriodTick = await tick({
      timestamp: demandFactorSettings.periodZeroStartTimestamp,
      memory: sharedMemory,
    });
    const initialDemandFactor = await getDemandFactor({
      memory: firstDemandFactorPeriodTick.memory,
      timestamp: demandFactorSettings.periodZeroStartTimestamp,
    });
    assert.equal(initialDemandFactor, 1);

    // get the base registration fee at the beginning of the demand factor period
    const genesisFee = await getBaseRegistrationFeeForName({
      memory: firstDemandFactorPeriodTick.memory,
      timestamp: demandFactorSettings.periodZeroStartTimestamp,
    });
    assert.equal(genesisFee, 600_000_000);

    const fundedUser = 'funded-user-'.padEnd(43, '1');
    const processId = 'process-id-'.padEnd(43, '1');
    const transferMemory = await transfer({
      recipient: fundedUser,
      quantity: 100_000_000_000_000,
      memory: firstDemandFactorPeriodTick.memory,
      timestamp: demandFactorSettings.periodZeroStartTimestamp,
    });

    // reset token supply before any buy records are bought
    const resetTokenSupplyMemory = await totalTokenSupply({
      memory: transferMemory,
      timestamp: demandFactorSettings.periodZeroStartTimestamp,
    });

    // Buy records in this epoch
    let buyRecordMemory = resetTokenSupplyMemory;
    for (let i = 0; i < 10; i++) {
      const { result: buyRecordResult } = await buyRecord({
        memory: buyRecordMemory,
        from: fundedUser,
        name: `test-name-${i}`,
        purchaseType: 'permabuy',
        processId: processId,
        timestamp: demandFactorSettings.periodZeroStartTimestamp,
      });
      buyRecordMemory = buyRecordResult.Memory;
    }

    // Tick to the half way through the first demand factor period
    const nextDemandFactorPeriodTimestamp =
      demandFactorSettings.periodZeroStartTimestamp +
      demandFactorSettings.periodLengthMs;
    const firstDemandFactorPeriodMidTick = await tick({
      memory: buyRecordMemory,
      timestamp: nextDemandFactorPeriodTimestamp / 2,
    });
    const feeDuringFirstDemandFactorPeriod =
      await getBaseRegistrationFeeForName({
        memory: firstDemandFactorPeriodMidTick.memory,
        timestamp: nextDemandFactorPeriodTimestamp / 2,
      });

    assert.equal(feeDuringFirstDemandFactorPeriod, 600_000_000);
    const firstPeriodDemandFactor = await getDemandFactor({
      memory: firstDemandFactorPeriodMidTick.memory,
      timestamp: nextDemandFactorPeriodTimestamp,
    });
    assert.equal(firstPeriodDemandFactor, 1);

    // Tick to the end of the first demand factor period
    const nextDemandFactorPeriodTick = await tick({
      memory: firstDemandFactorPeriodMidTick.memory,
      timestamp: nextDemandFactorPeriodTimestamp,
    });
    // get the demand factor after the period has incremented and demand factor has been adjusted
    const nextDemandFactorPeriodDemandFactor = await getDemandFactor({
      memory: nextDemandFactorPeriodTick.memory,
      timestamp: nextDemandFactorPeriodTimestamp,
    });
    assert.equal(nextDemandFactorPeriodDemandFactor, 1.0500000000000000444);
    // assert the demand factor is applied to the base registration fee for a name
    const nextDemandFactorPeriodFee = await getBaseRegistrationFeeForName({
      memory: nextDemandFactorPeriodTick.memory,
      timestamp: nextDemandFactorPeriodTimestamp,
    });
    assert.equal(nextDemandFactorPeriodFee, 630_000_000);
  });

  it('should reset to baseRegistrationFee when demandFactor is 0.5 for consecutive epochs', async () => {
    const demandFactorSettings = await getDemandFactorSettings({
      memory: sharedMemory,
    });
    const zeroPeriodDemandFactorTick = await tick({
      memory: sharedMemory,
      timestamp: demandFactorSettings.periodZeroStartTimestamp,
    });

    const baseFeeAtFirstDemandFactorPeriod =
      await getBaseRegistrationFeeForName({
        memory: zeroPeriodDemandFactorTick.memory,
        timestamp: demandFactorSettings.periodZeroStartTimestamp,
      });
    assert.equal(baseFeeAtFirstDemandFactorPeriod, 600_000_000);

    let tickMemory = zeroPeriodDemandFactorTick.memory;

    // Tick to the epoch where demandFactor is 0.5
    for (let i = 0; i <= 49; i++) {
      const nextDemandFactorPeriodTimestamp =
        demandFactorSettings.periodZeroStartTimestamp +
        demandFactorSettings.periodLengthMs * i;
      const nextDemandFactorPeriodTick = await tick({
        memory: tickMemory,
        timestamp: nextDemandFactorPeriodTimestamp,
      });

      tickMemory = nextDemandFactorPeriodTick.memory;

      if (i === 45) {
        const demandFactor = await getDemandFactor({
          memory: tickMemory,
          timestamp: nextDemandFactorPeriodTimestamp,
        });
        assert.equal(demandFactor, 0.50655939255251769548);
      }

      if ([46, 47, 48].includes(i)) {
        const demandFactor = await getDemandFactor({
          memory: tickMemory,
          timestamp: nextDemandFactorPeriodTimestamp,
        });
        assert.equal(demandFactor, 0.5);
      }
    }
    const demandFactorReadjustFeesTimestamp =
      demandFactorSettings.periodZeroStartTimestamp +
      demandFactorSettings.periodLengthMs * 50;
    const demandFactorAfterFeeAdjustment = await getDemandFactor({
      memory: tickMemory,
      timestamp: demandFactorReadjustFeesTimestamp,
    });
    const baseFeeAfterConsecutiveTicksWithNoPurchases =
      await getBaseRegistrationFeeForName({
        memory: tickMemory,
        timestamp: demandFactorReadjustFeesTimestamp,
      });

    assert.equal(demandFactorAfterFeeAdjustment, 1);
    assert.equal(baseFeeAfterConsecutiveTicksWithNoPurchases, 300_000_000);
    sharedMemory = tickMemory;
    lastTimestamp = demandFactorReadjustFeesTimestamp;
  });
});
