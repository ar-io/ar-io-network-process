import { assertNoResultError, createAosLoader } from './utils.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  validGatewayTags,
  PROCESS_OWNER,
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
  startMemory,
  returnedNamesPeriod,
} from './helpers.mjs';

const genesisEpochStart = 1722837600000 + 1;
const epochDurationMs = 60 * 1000 * 60 * 24; // 24 hours
const distributionDelayMs = 60 * 1000 * 40; // 40 minutes (~ 20 arweave blocks)

describe('Tick', async () => {
  const transfer = async ({
    recipient = STUB_ADDRESS,
    quantity = 100_000_000_000,
    memory = startMemory,
  } = {}) => {
    const transferResult = await handle({
      options: {
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
    });

    // assert no error tag
    const errorTag = transferResult.Messages?.[0]?.Tags?.find(
      (tag) => tag.Name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return transferResult.Memory;
  };

  it('should prune record that are expired and after the grace period and create returned names for them', async () => {
    let memory = startMemory;
    const buyRecordResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: 'test-name' },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: ''.padEnd(43, 'a') },
        ],
      },
      memory,
    });
    const realRecord = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      memory: buyRecordResult.Memory,
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
    const futureTickResult = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: futureTimestamp.toString() },
        ],
      },
      memory: buyRecordResult.Memory,
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
  });

  it('should prune gateways that are expired', async () => {
    const memory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 100_000_000_000,
    });

    const joinNetworkResult = await handle({
      options: {
        Tags: validGatewayTags(),
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
      },
      memory,
    });

    // assert no error tag
    assertNoResultError(joinNetworkResult);

    // check the gateway record from contract
    const gateway = await getGateway({
      memory: joinNetworkResult.Memory,
      address: STUB_ADDRESS,
    });
    assert.deepEqual(gateway.status, 'joined');

    // leave the network
    const leaveNetworkResult = await handle({
      options: {
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
        Tags: [{ name: 'Action', value: 'Leave-Network' }],
      },
      memory: joinNetworkResult.Memory,
    });

    // check the gateways status is leaving
    const leavingGateway = await getGateway({
      memory: leaveNetworkResult.Memory,
      address: STUB_ADDRESS,
    });
    assert.deepEqual(leavingGateway.status, 'leaving');
    // TODO: check delegates and operator stake are vaulted

    // expedite the timestamp to the future
    const futureTimestamp = leavingGateway.endTimestamp + 1;
    const futureTick = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: futureTimestamp.toString() },
        ],
      },
      memory: leaveNetworkResult.Memory,
    });

    // check the gateway is pruned
    const prunedGateway = await getGateway({
      memory: futureTick.Memory,
      address: STUB_ADDRESS,
    });

    assert.deepEqual(undefined, prunedGateway);
  });

  // vaulting is not working as expected, need to fix before enabling this test
  it('should prune vaults that are expired', async () => {
    const lockLengthMs = 1209600000;
    const quantity = 1000000000;
    const balanceBefore = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Balance' }],
      },
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
    const futureTick = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: futureTimestamp,
      },
      memory: createVaultResult.Memory,
    });

    // check the vault is pruned
    const prunedVault = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Vault' }],
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
      },
      memory: futureTick.Memory,
    });
    const balanceData = JSON.parse(ownerBalance.Messages[0].Data);
    assert.equal(balanceData, balanceBeforeData);
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
    const epochSettings = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Epoch-Settings' }],
      },
    });
    const epochSettingsData = JSON.parse(epochSettings.Messages?.[0]?.Data);
    const genesisEpochTimestamp = epochSettingsData.epochZeroStartTimestamp;
    // now tick to create the first epoch after the epoch start timestamp
    const createEpochTimestamp = genesisEpochTimestamp + 1;
    const newEpochTick = await handle({
      options: {
        Timestamp: createEpochTimestamp, // one millisecond after the epoch start timestamp, should create the epoch and set the prescribed observers and names
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Force-Prune', value: 'true' }, // simply exercise this though it's not critical to the test
        ],
      },
      memory: newDelegateResult.Memory,
    });

    // assert no error tag
    assertNoResultError(newEpochTick);

    // assert the new epoch is created
    const epoch = await handle({
      options: {
        Timestamp: createEpochTimestamp, // one millisecond after the epoch start timestamp
        Tags: [{ name: 'Action', value: 'Epoch' }],
      },
      memory: newEpochTick.Memory,
    });

    // get the epoch timestamp and assert it is in 24 hours
    const protocolBalanceAtStartOfEpoch = 50_000_000_0000; // 50M ARIO
    const totalEligibleRewards = protocolBalanceAtStartOfEpoch * 0.05; // 5% of the protocol balance
    const totalGatewayRewards = Math.ceil(totalEligibleRewards * 0.9); // 90% go to gateways
    const totalObserverRewards = Math.floor(totalEligibleRewards * 0.1); // 10% go to observers
    const totalEligibleGatewayRewards =
      (totalGatewayRewards + totalObserverRewards) / 1; // only one gateway in the network
    const expectedGatewayOperatorReward = totalEligibleGatewayRewards * 0.75; // 75% of the eligible rewards go to the operator
    const expectedGatewayDelegateReward = totalEligibleGatewayRewards * 0.25; // 25% of the eligible rewards go to the delegates
    const epochData = JSON.parse(epoch.Messages[0].Data);
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
          // TODO: we could just return the addresses here
          observerAddress: STUB_ADDRESS,
          observerRewardRatioWeight: 1,
          normalizedCompositeWeight: 1,
          gatewayRewardRatioWeight: 1,
          gatewayAddress: STUB_ADDRESS,
          stake: INITIAL_OPERATOR_STAKE * 3,
          tenureWeight: 4,
          compositeWeight: 12,
          startTimestamp: 21600000,
          stakeWeight: 3,
        },
      ], // the only gateway in the network
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
    const observation = await handle({
      options: {
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
        Timestamp: observationTimestamp,
        Tags: [
          { name: 'Action', value: 'Save-Observations' },
          {
            name: 'Report-Tx-Id',
            value: reportTxId,
          },
        ],
      },
      memory: epoch.Memory,
    });

    // assert no error tag
    assertNoResultError(observation);

    // now jump ahead to the epoch distribution timestamp
    const distributionTimestamp = epochData.distributionTimestamp;
    const distributionTick = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: distributionTimestamp,
      },
      memory: observation.Memory,
    });

    // assert no error tag
    assertNoResultError(distributionTick);

    // check the rewards were distributed correctly
    const rewards = await handle({
      options: {
        Timestamp: distributionTimestamp,
        Tags: [
          { name: 'Action', value: 'Epoch' },
          {
            name: 'Epoch-Index',
            value: '0',
          },
        ],
      },
      memory: distributionTick.Memory,
    });

    const distributedEpochData = JSON.parse(rewards.Messages[0].Data);
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
    });
    // assert the new epoch was created
    const newEpoch = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Epoch' }],
        Timestamp: distributionTimestamp,
      },
      memory: distributionTick.Memory,
    });
    const newEpochData = JSON.parse(newEpoch.Messages[0].Data);
    assert.equal(newEpochData.epochIndex, 1);
    // assert the gateway stakes were updated and match the distributed rewards
    const gateway = await getGateway({
      memory: distributionTick.Memory,
      address: STUB_ADDRESS,
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
      memory: distributionTick.Memory,
      gatewayAddress: STUB_ADDRESS,
    });
    assert.deepEqual(delegateItems, [
      {
        delegatedStake: delegateQuantity + expectedGatewayDelegateReward,
        startTimestamp: delegateTimestamp,
        address: delegateAddress,
      },
    ]);
  });

  it('should not increase demandFactor and baseRegistrationFee when records are bought until the end of the epoch', async () => {
    const genesisEpochTick = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: genesisEpochStart,
      },
      memory: startMemory,
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
  });

  it('should reset to baseRegistrationFee when demandFactor is 0.5 for consecutive epochs', async () => {
    const zeroEpochTick = await handle({
      options: {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: genesisEpochStart,
      },
      memory: startMemory,
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
      const { Memory } = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Tick' },
            { name: 'Timestamp', value: epochTimestamp.toString() },
          ],
          Timestamp: epochTimestamp,
        },
        memory: tickMemory,
      });
      tickMemory = Memory;

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
  });
});
