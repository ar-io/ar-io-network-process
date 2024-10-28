import { createAosLoader } from './utils.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  validGatewayTags,
  PROCESS_OWNER,
  PROCESS_ID,
  STUB_TIMESTAMP,
} from '../tools/constants.mjs';

describe('Tick', async () => {
  const { handle: originalHandle, memory: startMemory } =
    await createAosLoader();

  async function handle(options = {}, mem = startMemory) {
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
    quantity = 100_000_000_000,
    memory = startMemory,
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
      (tag) => tag.Name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return transferResult.Memory;
  };

  it('should prune record that are expired and after the grace period and create auctions for them', async () => {
    let mem = startMemory;
    const buyRecordResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: 'test-name' },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: ''.padEnd(43, 'a') },
        ],
      },
      mem,
    );

    const realRecord = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      buyRecordResult.Memory,
    );

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
    const futureTickResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: futureTimestamp.toString() },
        ],
      },
      buyRecordResult.Memory,
    );

    const tickEvent = JSON.parse(
      futureTickResult.Output.data
        .split('\n')
        .filter((line) => line.includes('_e'))[0],
    );
    assert.equal(tickEvent['Records-Count'], 0);
    assert.equal(tickEvent['Pruned-Records-Count'], 1);
    assert.deepEqual(tickEvent['Pruned-Records'], ['test-name']);

    // the record should be pruned
    const prunedRecord = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      futureTickResult.Memory,
    );

    const prunedRecordData = JSON.parse(prunedRecord.Messages[0].Data);

    assert.deepEqual(undefined, prunedRecordData);

    // the auction should have been created
    const auctionData = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Auction-Info' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      futureTickResult.Memory,
    );
    const auctionInfoData = JSON.parse(auctionData.Messages[0].Data);
    assert.deepEqual(auctionInfoData, {
      name: 'test-name',
      startTimestamp: futureTimestamp,
      endTimestamp: futureTimestamp + 60 * 1000 * 60 * 24 * 14,
      initiator: PROCESS_ID,
      baseFee: 500000000,
      demandFactor: 1,
      settings: {
        decayRate: 0.02037911 / (1000 * 60 * 60 * 24 * 14),
        scalingExponent: 190,
        startPriceMultiplier: 50,
        durationMs: 60 * 1000 * 60 * 24 * 14,
      },
    });
  });

  it('should prune gateways that are expired', async () => {
    const memory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 100_000_000_000,
    });

    const joinNetworkResult = await handle(
      {
        Tags: validGatewayTags,
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
      },
      memory,
    );

    // assert no error tag
    const errorTag = joinNetworkResult.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    // check the gateway record from contract
    const gateway = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Gateway' },
          { name: 'Address', value: STUB_ADDRESS },
        ],
      },
      joinNetworkResult.Memory,
    );
    const gatewayData = JSON.parse(gateway.Messages[0].Data);
    assert.deepEqual(gatewayData.status, 'joined');

    // leave the network
    const leaveNetworkResult = await handle(
      {
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
        Tags: [{ name: 'Action', value: 'Leave-Network' }],
      },
      joinNetworkResult.Memory,
    );

    // check the gateways status is leaving
    const leavingGateway = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Gateway' },
          { name: 'Address', value: STUB_ADDRESS },
        ],
      },
      leaveNetworkResult.Memory,
    );

    const leavingGatewayData = JSON.parse(leavingGateway.Messages[0].Data);
    assert.deepEqual(leavingGatewayData.status, 'leaving');
    // TODO: check delegates and operator stake are vaulted

    // expedite the timestamp to the future
    const futureTimestamp = leavingGatewayData.endTimestamp + 1;
    const futureTick = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: futureTimestamp.toString() },
        ],
      },
      leaveNetworkResult.Memory,
    );

    // check the gateway is pruned
    const prunedGateway = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Gateway' },
          { name: 'Address', value: STUB_ADDRESS },
        ],
      },
      futureTick.Memory,
    );

    const prunedGatewayData = JSON.parse(prunedGateway.Messages[0].Data);
    assert.deepEqual(undefined, prunedGatewayData);
  });

  // vaulting is not working as expected, need to fix before enabling this test
  it('should prune vaults that are expired', async () => {
    const lockLengthMs = 1209600000;
    const quantity = 1000000000;
    const balanceBefore = await handle({
      Tags: [{ name: 'Action', value: 'Balance' }],
    });
    const balanceBeforeData = JSON.parse(balanceBefore.Messages[0].Data);
    const createVaultResult = await handle({
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
    const balanceAfterVault = await handle(
      {
        Tags: [{ name: 'Action', value: 'Balance' }],
      },
      createVaultResult.Memory,
    );
    const balanceAfterVaultData = JSON.parse(
      balanceAfterVault.Messages[0].Data,
    );
    assert.deepEqual(balanceAfterVaultData, balanceBeforeData - quantity);

    // check that vault exists
    const vault = await handle(
      {
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
      createVaultResult.Memory,
    );
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
    const futureTick = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: futureTimestamp.toString() },
        ],
      },
      createVaultResult.Memory,
    );

    // check the vault is pruned
    const prunedVault = await handle(
      {
        Tags: [{ name: 'Action', value: 'Vault' }],
      },
      futureTick.Memory,
    );
    assert.deepEqual(undefined, prunedVault.Messages[0].Data);
    assert.equal(
      prunedVault.Messages[0].Tags.find((tag) => tag.name === 'Error').value,
      'Vault-Not-Found',
    );

    // Check that the balance is returned to the owner
    const ownerBalance = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Balance' },
          { name: 'Target', value: DEFAULT_HANDLE_OPTIONS.Owner },
        ],
      },
      futureTick.Memory,
    );
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
    // add a gateway
    const newGateway = await handle(
      {
        Tags: validGatewayTags,
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
      },
      initialMemory,
    );

    // assert no error tag
    const errorTag = newGateway.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    // give balance to delegate
    const delegateQuantity = 50_000_000_000;
    const delegateTimestamp = STUB_TIMESTAMP + 1;
    const transferMemory = await transfer({
      recipient: delegateAddress,
      quantity: delegateQuantity,
      memory: newGateway.Memory,
    });
    const newDelegate = await handle(
      {
        Tags: [
          {
            name: 'Action',
            value: 'Delegate-Stake',
          },
          {
            name: 'Quantity',
            value: delegateQuantity.toString(),
          },
          {
            name: 'Address',
            value: STUB_ADDRESS,
          },
        ],
        From: delegateAddress,
        Owner: delegateAddress,
        Timestamp: delegateTimestamp,
      },
      transferMemory,
    );

    // assert no error tag
    const delegateErrorTag = newDelegate.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(delegateErrorTag, undefined);

    // fast forward to the start of the first epoch
    const epochSettings = await handle({
      Tags: [{ name: 'Action', value: 'Epoch-Settings' }],
    });
    const epochSettingsData = JSON.parse(epochSettings.Messages?.[0]?.Data);
    const genesisEpochTimestamp = epochSettingsData.epochZeroStartTimestamp;
    // now tick to create the first epoch after the epoch start timestamp
    const createEpochTimestamp = genesisEpochTimestamp + 1;
    const newEpochTick = await handle(
      {
        Timestamp: createEpochTimestamp, // one millisecond after the epoch start timestamp, should create the epoch and set the prescribed observers and names
        Tags: [{ name: 'Action', value: 'Tick' }],
      },
      newDelegate.Memory,
    );

    // assert no error tag
    const tickErrorTag = newEpochTick.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(tickErrorTag, undefined);

    // assert the new epoch is created
    const epoch = await handle(
      {
        Timestamp: createEpochTimestamp, // one millisecond after the epoch start timestamp
        Tags: [{ name: 'Action', value: 'Epoch' }],
      },
      newEpochTick.Memory,
    );

    // get the epoch timestamp and assert it is in 24 hours
    const protocolBalanceAtStartOfEpoch = 50_000_000_0000; // 50M IO
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
          stake: 150000000000,
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
    const observation = await handle(
      {
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
      epoch.Memory,
    );

    // assert no error tag
    const observationErrorTag = observation.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(observationErrorTag, undefined);

    // now jump ahead to the epoch distribution timestamp
    const distributionTimestamp = epochData.distributionTimestamp;
    const distributionTick = await handle(
      {
        Tags: [{ name: 'Action', value: 'Tick' }],
        Timestamp: distributionTimestamp,
      },
      observation.Memory,
    );

    // assert no error tag
    const distributionTickErrorTag = distributionTick.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
    );
    assert.strictEqual(distributionTickErrorTag, undefined);

    // check the rewards were distributed correctly
    const rewards = await handle(
      {
        Timestamp: distributionTimestamp,
        Tags: [
          { name: 'Action', value: 'Epoch' },
          {
            name: 'Epoch-Index',
            value: '0',
          },
        ],
      },
      distributionTick.Memory,
    );

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
    const newEpoch = await handle(
      {
        Tags: [{ name: 'Action', value: 'Epoch' }],
        Timestamp: distributionTimestamp,
      },
      distributionTick.Memory,
    );
    const newEpochData = JSON.parse(newEpoch.Messages[0].Data);
    assert.equal(newEpochData.epochIndex, 1);
    // assert the gateway stakes were updated and match the distributed rewards
    const gateway = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Gateway' },
          { name: 'Address', value: STUB_ADDRESS },
        ],
        Timestamp: distributionTimestamp,
      },
      distributionTick.Memory,
    );
    const gatewayData = JSON.parse(gateway.Messages[0].Data);
    assert.deepStrictEqual(gatewayData, {
      status: 'joined',
      vaults: [],
      startTimestamp: STUB_TIMESTAMP,
      observerAddress: STUB_ADDRESS,
      operatorStake: 100_000_000_000 + expectedGatewayOperatorReward,
      totalDelegatedStake: 50_000_000_000 + expectedGatewayDelegateReward,
      delegates: {
        [delegateAddress]: {
          delegatedStake: 50_000_000_000 + expectedGatewayDelegateReward,
          startTimestamp: delegateTimestamp,
          vaults: [],
        },
      },
      settings: {
        allowDelegatedStaking: true,
        autoStake: true,
        delegateRewardShareRatio: 25,
        minDelegatedStake: 500_000_000,
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
        compositeWeight: 14,
        gatewayRewardRatioWeight: 1,
        normalizedCompositeWeight: 1,
        observerRewardRatioWeight: 1,
        stakeWeight: 3.5,
        tenureWeight: 4,
      },
    });
  });
});
