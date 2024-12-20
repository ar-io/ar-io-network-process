import { assertNoResultError } from './utils.mjs';
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import {
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  PROCESS_ID,
  STUB_TIMESTAMP,
  INITIAL_OPERATOR_STAKE,
  INITIAL_DELEGATE_STAKE,
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
} from './helpers.mjs';
import { assertNoInvariants } from './invariants.mjs';

const genesisEpochStart = 1722837600000 + 1;
const epochDurationMs = 60 * 1000 * 60 * 24; // 24 hours
const distributionDelayMs = 60 * 1000 * 40; // 40 minutes (~ 20 arweave blocks)

describe('Tick', async () => {
  let sharedMemory;
  beforeEach(async () => {
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    sharedMemory = totalTokenSupplyMemory;
  });

  afterEach(async () => {
    await assertNoInvariants({
      timestamp: genesisEpochStart + 1000 * 60 * 60 * 24 * 365,
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
   */
  it('should distribute rewards to gateways and delegates', async () => {
    // give balance to gateway
    const initialMemory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 100_000_000_000,
      memory: sharedMemory,
    });

    const delegateAddress = 'delegate-address-'.padEnd(43, '1');
    // add the gateway
    const { result: newGateway } = await joinNetwork({
      memory: initialMemory,
      address: STUB_ADDRESS,
      timestamp: STUB_TIMESTAMP,
    });

    // assert no error tag
    assertNoResultError(newGateway);

    // give balance to delegate and stake - making the gateway weight 3 * the minimum
    const delegateQuantity = INITIAL_OPERATOR_STAKE * 2;
    const delegateTimestamp = STUB_TIMESTAMP + 1;
    const transferMemory = await transfer({
      recipient: delegateAddress,
      quantity: delegateQuantity,
      memory: newGateway.Memory,
    });
    const { result: newDelegateResult } = await delegateStake({
      gatewayAddress: STUB_ADDRESS,
      delegatorAddress: delegateAddress,
      quantity: delegateQuantity,
      timestamp: delegateTimestamp,
      memory: transferMemory,
    });

    // assert no error tag
    assertNoResultError(newDelegateResult);

    // fast forward to the start of the first epoch
    const epochSettings = await getEpochSettings({
      memory: newDelegateResult.Memory,
      timestamp: delegateTimestamp,
    });
    const genesisEpochTimestamp = epochSettings.epochZeroStartTimestamp;
    // now tick to create the first epoch after the epoch start timestamp
    const createEpochTimestamp = genesisEpochTimestamp + 1;
    const newEpochTick = await tick({
      memory: newDelegateResult.Memory,
      timestamp: createEpochTimestamp,
      forcePrune: true,
    });

    // assert no error tag
    assertNoResultError(newEpochTick);

    // assert the new epoch is created
    const epochData = await getEpoch({
      memory: newEpochTick.memory,
      timestamp: createEpochTimestamp,
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
    assert.deepStrictEqual(epochData, {
      epochIndex: 0,
      startHeight: 1,
      startTimestamp: genesisEpochTimestamp,
      endTimestamp: genesisEpochTimestamp + 24 * 1000 * 60 * 60, // 24 hours - this should match the epoch settings
      distributionTimestamp:
        genesisEpochTimestamp + 24 * 1000 * 60 * 60 + 40 * 60 * 1000, // 24 hours + 40 minutes
      observations: {
        failureSummaries: [],
        reports: [],
      },
      prescribedObservers: [
        {
          observerAddress: STUB_ADDRESS,
          gatewayAddress: STUB_ADDRESS,
          stakeWeight: 3,
          gatewayRewardRatioWeight: 1,
          observerRewardRatioWeight: 1,
          compositeWeight: 12,
          normalizedCompositeWeight: 1,
          tenureWeight: 4,
          stake: INITIAL_OPERATOR_STAKE,
          startTimestamp: STUB_TIMESTAMP,
        },
      ],
      prescribedNames: [], // no names in the network
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
    const observationTimestamp = createEpochTimestamp + 7 * 1000 * 60 * 60; // 7 hours after the epoch start timestamp
    const observation = await saveObservations({
      memory: newEpochTick.memory,
      timestamp: observationTimestamp,
      from: STUB_ADDRESS,
      reportTxId,
    });

    // assert no error tag
    assertNoResultError(observation);

    // now jump ahead to the epoch distribution timestamp
    const distributionTimestamp = epochData.distributionTimestamp;
    const distributionTick = await tick({
      memory: observation.memory,
      timestamp: distributionTimestamp,
    });

    // assert no error tag
    assertNoResultError(distributionTick);

    // check the rewards were distributed correctly and weights are updated
    const distributedEpochData = await getEpoch({
      memory: distributionTick.memory,
      timestamp: distributionTimestamp,
      epochIndex: 0,
    });

    assert.deepStrictEqual(distributedEpochData, {
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
      prescribedObservers: [
        {
          ...epochData.prescribedObservers[0],
          stake: INITIAL_OPERATOR_STAKE + expectedGatewayOperatorReward,
          compositeWeight: 22,
          stakeWeight: 5.5,
        },
      ],
    });
    // assert the new epoch was created
    const newEpoch = await getEpoch({
      memory: distributionTick.memory,
      timestamp: distributionTimestamp,
      epochIndex: 1,
    });
    assert.equal(newEpoch.epochIndex, 1);
    // assert the gateway stakes were updated and match the distributed rewards
    const gateway = await getGateway({
      memory: distributionTick.memory,
      address: STUB_ADDRESS,
      timestamp: distributionTimestamp,
    });
    assert.deepStrictEqual(gateway, {
      status: 'joined',
      startTimestamp: STUB_TIMESTAMP,
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
        compositeWeight: 22,
        gatewayRewardRatioWeight: 1,
        normalizedCompositeWeight: 1,
        observerRewardRatioWeight: 1,
        stakeWeight: 5.5,
        tenureWeight: 4,
      },
    });

    const delegateItems = await getDelegatesItems({
      memory: distributionTick.memory,
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
    sharedMemory = distributionTick.memory;
  });

  it('should not increase demandFactor and baseRegistrationFee when records are bought until the end of the epoch', async () => {
    const genesisEpochTick = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: genesisEpochStart,
      },
      memory: sharedMemory,
    });
    const genesisFee = await getBaseRegistrationFeeForName({
      memory: genesisEpochTick.Memory,
      timestamp: genesisEpochStart,
    });
    assert.equal(genesisFee, 600_000_000);

    const zeroTickDemandFactorResult = await getDemandFactor({
      memory: genesisEpochTick.Memory,
      timestamp: genesisEpochStart,
    });
    assert.equal(zeroTickDemandFactorResult, 1);

    const fundedUser = 'funded-user-'.padEnd(43, '1');
    const processId = 'process-id-'.padEnd(43, '1');
    const transferMemory = await transfer({
      recipient: fundedUser,
      quantity: 100_000_000_000_000,
      memory: genesisEpochTick.Memory,
      timestamp: genesisEpochStart,
    });

    // Buy records in this epoch
    let buyRecordMemory = transferMemory;
    for (let i = 0; i < 10; i++) {
      const { result: buyRecordResult } = await buyRecord({
        memory: buyRecordMemory,
        from: fundedUser,
        name: `test-name-${i}`,
        purchaseType: 'permabuy',
        processId: processId,
        timestamp: genesisEpochStart,
      });
      buyRecordMemory = buyRecordResult.Memory;
    }

    // Tick to the half way through the first epoch
    const firstEpochMidTimestamp = genesisEpochStart + epochDurationMs / 2;
    const firstEpochMidTick = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: firstEpochMidTimestamp,
      },
      memory: buyRecordMemory,
    });
    const feeDuringFirstEpoch = await getBaseRegistrationFeeForName({
      memory: firstEpochMidTick.Memory,
      timestamp: firstEpochMidTimestamp + 1,
    });

    assert.equal(feeDuringFirstEpoch, 600_000_000);
    const firstEpochDemandFactorResult = await getDemandFactor({
      memory: firstEpochMidTick.Memory,
      timestamp: firstEpochMidTimestamp + 1,
    });
    assert.equal(firstEpochDemandFactorResult, 1);

    // Tick to the end of the first epoch
    const firstEpochEndTimestamp =
      genesisEpochStart + epochDurationMs + distributionDelayMs + 1;
    const firstEpochEndTick = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: firstEpochEndTimestamp,
      },
      memory: buyRecordMemory,
    });
    const feeAfterFirstEpochEnd = await getBaseRegistrationFeeForName({
      memory: firstEpochEndTick.Memory,
      timestamp: firstEpochEndTimestamp + 1,
    });

    assert.equal(feeAfterFirstEpochEnd, 630_000_000);

    const firstEpochEndDemandFactorResult = await getDemandFactor({
      memory: firstEpochEndTick.Memory,
      timestamp: firstEpochEndTimestamp + 1,
    });
    assert.equal(firstEpochEndDemandFactorResult, 1.0500000000000000444);
    sharedMemory = firstEpochEndTick.Memory;
  });

  it('should reset to baseRegistrationFee when demandFactor is 0.5 for consecutive epochs', async () => {
    const zeroEpochTick = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: genesisEpochStart,
      },
      memory: sharedMemory,
    });

    const baseFeeAtZeroEpoch = await getBaseRegistrationFeeForName({
      memory: zeroEpochTick.Memory,
      timestamp: genesisEpochStart,
    });
    assert.equal(baseFeeAtZeroEpoch, 600_000_000);

    let tickMemory = zeroEpochTick.Memory;

    // Tick to the epoch where demandFactor is 0.5
    for (let i = 0; i <= 49; i++) {
      const epochTimestamp = genesisEpochStart + (epochDurationMs + 1) * i;
      const { result: tickResult } = await tick({
        memory: tickMemory,
        timestamp: epochTimestamp,
      });
      tickMemory = tickResult.Memory;

      if (i === 45) {
        const demandFactor = await getDemandFactor({
          memory: tickMemory,
          timestamp: epochTimestamp,
        });
        assert.equal(demandFactor, 0.50655939255251769548);
      }

      if ([46, 47, 48].includes(i)) {
        const demandFactor = await getDemandFactor({
          memory: tickMemory,
          timestamp: epochTimestamp,
        });
        assert.equal(demandFactor, 0.5);
      }
    }

    const afterTimestamp = genesisEpochStart + (epochDurationMs + 1) * 50;
    const demandFactorAfterFeeAdjustment = await getDemandFactor({
      memory: tickMemory,
      timestamp: afterTimestamp,
    });
    const baseFeeAfterConsecutiveTicksWithNoPurchases =
      await getBaseRegistrationFeeForName({
        memory: tickMemory,
        timestamp: afterTimestamp,
      });

    assert.equal(demandFactorAfterFeeAdjustment, 1);
    assert.equal(baseFeeAfterConsecutiveTicksWithNoPurchases, 300_000_000);
    sharedMemory = tickMemory;
  });
});
