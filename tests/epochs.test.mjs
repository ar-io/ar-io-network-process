import {
  buyRecord,
  getEpoch,
  joinNetwork,
  getPrescribedObservers,
  getPrescribedNames,
  tick,
  startMemory,
  totalTokenSupply,
  getEpochSettings,
  getBalance,
  getGateway,
  getEligibleDistributions,
} from './helpers.mjs';
import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import {
  INITIAL_OPERATOR_STAKE,
  PROCESS_ID,
  STUB_ADDRESS,
  STUB_HASH_CHAIN,
  STUB_OPERATOR_ADDRESS,
  STUB_TIMESTAMP,
} from '../tools/constants.mjs';

describe('epochs', () => {
  let sharedMemory;
  let firstEpoch;
  let epochSettings;
  let protocolBalanceAfterNamePurchase;

  before(async () => {
    epochSettings = await getEpochSettings({
      memory: startMemory,
      timestamp: STUB_TIMESTAMP,
    });
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
      timestamp: 0,
    });
    // have a gateway join, and add an arns name which will be used to prescribe names and observers
    const { memory: gatewayJoinMemory } = await joinNetwork({
      memory: totalTokenSupplyMemory,
      address: STUB_OPERATOR_ADDRESS,
      timestamp: 0,
    });
    const { memory: buyRecordMemory } = await buyRecord({
      memory: gatewayJoinMemory,
      name: 'prescribed-name',
      type: 'permabuy',
      from: STUB_OPERATOR_ADDRESS,
      timestamp: 0,
    });
    protocolBalanceAfterNamePurchase = await getBalance({
      memory: buyRecordMemory,
      address: PROCESS_ID,
    });
    sharedMemory = buyRecordMemory;
  });

  describe('Epochs', () => {
    describe('Create First Epoch', () => {
      it('should not create the epoch if the timestamp is before the epoch zero start timestamp', async () => {
        const { memory: tickMemory } = await tick({
          memory: sharedMemory,
          timestamp: epochSettings.epochZeroStartTimestamp - 1,
        });
        const epoch = await getEpoch({
          memory: tickMemory,
          timestamp: epochSettings.epochZeroStartTimestamp - 1,
        });
        assert.deepStrictEqual(epoch, null);
        sharedMemory = tickMemory;
      });

      it('should create, prescribe, and assign eligible rewards for the first epoch at epoch zero start timestamp', async () => {
        const { memory: tickMemory } = await tick({
          memory: sharedMemory,
          timestamp: epochSettings.epochZeroStartTimestamp,
        });
        const epoch = await getEpoch({
          memory: tickMemory,
          timestamp: epochSettings.epochZeroStartTimestamp,
        });
        const expectedEligibleRewards =
          protocolBalanceAfterNamePurchase * 0.001; // 0.1% of the protocol balance after the transfers and name purchase
        const expectedGatewayRewards = expectedEligibleRewards * 0.9; // 90% go to gateways
        const expectedObserverRewards = expectedEligibleRewards * 0.1; // 10% go to observers
        assert.deepStrictEqual(epoch, {
          epochIndex: 0,
          hashchain: STUB_HASH_CHAIN,
          startTimestamp: epochSettings.epochZeroStartTimestamp,
          endTimestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
          startHeight: 1,
          arnsStats: {
            totalActiveNames: 1,
            totalGracePeriodNames: 0,
            totalReservedNames: 0,
            totalReturnedNames: 0,
          },
          prescribedObservers: [],
          prescribedNames: [],
          observations: {
            failureSummaries: [], // TODO: ideally this is encoded as an empty object, consider adding a helper function to encode empty objects
            reports: [], // TODO: ideally this is encoded as an empty object, consider adding a helper function to encode empty objects
          },
          prescribedObservers: [
            {
              observerAddress: STUB_ADDRESS,
              gatewayAddress: STUB_OPERATOR_ADDRESS,
              stakeWeight: 1,
              gatewayPerformanceRatio: 1,
              observerPerformanceRatio: 1,
              compositeWeight: 4,
              normalizedCompositeWeight: 1,
              tenureWeight: 4,
              stake: INITIAL_OPERATOR_STAKE,
              startTimestamp: 0,
            },
          ],
          prescribedNames: ['prescribed-name'],
          distributions: {
            totalEligibleGatewayReward: expectedGatewayRewards,
            totalEligibleGateways: 1,
            totalEligibleObserverReward: expectedObserverRewards,
            totalEligibleRewards: expectedEligibleRewards,
          },
        });
        firstEpoch = epoch;

        const eligibleDistributions = await getEligibleDistributions({
          memory: tickMemory,
          timestamp: epochSettings.epochZeroStartTimestamp,
        });

        assert.deepStrictEqual(eligibleDistributions, {
          hasMore: false,
          items: [
            {
              cursorId:
                'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE_EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE',
              eligibleReward: 50002000000,
              gatewayAddress: 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE',
              recipient: 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE',
              type: 'operatorReward',
            },
          ],
          limit: 100,
          sortBy: 'cursorId',
          sortOrder: 'desc',
          totalItems: 1,
        });

        sharedMemory = tickMemory;
      });

      it('should return the an empty array for the prescribed observers if the epoch has not been prescribed', async () => {
        const prescribedObservers = await getPrescribedObservers({
          memory: sharedMemory,
          timestamp: epochSettings.epochZeroStartTimestamp - 1,
        });
        assert.deepStrictEqual(prescribedObservers, []);
      });

      it('should return an empty array for the prescribed names if the epoch has not been prescribed', async () => {
        const prescribedNames = await getPrescribedNames({
          memory: sharedMemory,
          timestamp: epochSettings.epochZeroStartTimestamp - 1,
        });
        assert.deepStrictEqual(prescribedNames, []);
      });

      it('should return the prescribed observers for the current epoch with weights', async () => {
        const prescribedObservers = await getPrescribedObservers({
          memory: sharedMemory,
          timestamp: epochSettings.epochZeroStartTimestamp,
        });
        assert.deepStrictEqual(prescribedObservers, [
          {
            compositeWeight: 4,
            gatewayAddress: STUB_OPERATOR_ADDRESS,
            gatewayPerformanceRatio: 1,
            normalizedCompositeWeight: 1,
            observerAddress: STUB_ADDRESS,
            observerPerformanceRatio: 1,
            stakeWeight: 1,
            stake: INITIAL_OPERATOR_STAKE,
            startTimestamp: 0,
            tenureWeight: 4,
          },
        ]);
      });

      it('should return the prescribed names once the epoch has been prescribed', async () => {
        const prescribedNames = await getPrescribedNames({
          memory: sharedMemory,
          timestamp: epochSettings.epochZeroStartTimestamp,
        });
        assert.deepStrictEqual(prescribedNames, ['prescribed-name']);
      });
    });

    describe('Create Second Epoch', () => {
      it('should distribute the last epoch, and create, prescribe, and assign eligible rewards for the next epoch at the epoch end timestamp', async () => {
        const protocolBalanceBeforeSecondEpochTick = await getBalance({
          memory: sharedMemory,
          address: PROCESS_ID,
          timestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
        });
        const gatewayBeforeTick = await getGateway({
          memory: sharedMemory,
          address: STUB_OPERATOR_ADDRESS,
          timestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
        });
        const { memory: tickMemory, result: tickResult } = await tick({
          memory: sharedMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
          blockHeight: 2, // for the next epoch, the block height is 2 (this is usually provided by the MU)
          hashchain: 'hashchain-'.padEnd(43, 'g'),
        });

        // the first epoch is now distributed
        const epochDistributionMessage = tickResult.Messages.find(
          (m) =>
            m.Tags.find((t) => t.name === 'Action').value ===
            'Epoch-Distribution-Notice',
        );
        const epochDistributionData = JSON.parse(epochDistributionMessage.Data);
        assert.deepStrictEqual(epochDistributionData, {
          ...firstEpoch,
          distributions: {
            ...firstEpoch.distributions,
            distributedTimestamp:
              epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
            totalDistributedRewards: 43876350000, // the result of the first tick
            rewards: {
              ...firstEpoch.distributions.rewards,
              eligible: {
                [STUB_OPERATOR_ADDRESS]: {
                  delegateRewards: [],
                  operatorReward: 50002000000,
                },
              },
              distributed: {
                [STUB_OPERATOR_ADDRESS]: 43876350000, // received the full operator reward, but docked 25% for not observing
              },
            },
          },
        });

        // it should be pruned from state after distribution notice sent
        const prunedEpoch = await getEpoch({
          memory: tickMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.durationMs +
            1,
          epochIndex: 0, // try and get the pruned epoch by epoch index even though it has been pruned
        });
        assert.deepStrictEqual(prunedEpoch, null);

        // the new epoch should be created and prescribed
        const secondEpoch = await getEpoch({
          memory: tickMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
        });

        const expectedEligibleRewards =
          protocolBalanceBeforeSecondEpochTick * 0.001; // 0.1% of the protocol balance after the transfers and name purchase
        const expectedGatewayRewards = expectedEligibleRewards * 0.9; // 90% go to gateways
        const expectedDistributedRewards = expectedGatewayRewards * 0.75; // the operator received 75% of the gateway rewards because they did not observe the first epoch
        const updatedOperatorStake =
          gatewayBeforeTick.operatorStake + expectedDistributedRewards;
        const expectedStakeWeight =
          updatedOperatorStake / INITIAL_OPERATOR_STAKE;
        const expectedTenureWeight = gatewayBeforeTick.weights.tenureWeight;
        const expectedGatewayPerformanceRatio = 1;
        const expectedObserverPerformanceRatio = 0.5; // the observer performance ratio is 0.5 because the operator did not observe the first epoch (we add 1 to the denominator to avoid division by zero - so 1/2 = 0.5)
        const expectedCompositeWeight =
          expectedStakeWeight *
          expectedTenureWeight *
          expectedGatewayPerformanceRatio *
          expectedObserverPerformanceRatio;
        const expectedNormalizedCompositeWeight = 1; // it's the only operator
        const expectedNewEligibleRewards =
          (protocolBalanceBeforeSecondEpochTick - expectedDistributedRewards) *
          0.001;
        const expectedSecondEpochObserverReward =
          expectedNewEligibleRewards * 0.1;
        const expectedSecondEpochGatewayReward =
          expectedNewEligibleRewards * 0.9;
        assert.deepStrictEqual(secondEpoch, {
          epochIndex: 1,
          hashchain: 'hashchain-'.padEnd(43, 'g'),
          startTimestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
          endTimestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.durationMs * 2,
          startHeight: 2,
          arnsStats: {
            totalActiveNames: 1,
            totalGracePeriodNames: 0,
            totalReservedNames: 0,
            totalReturnedNames: 0,
          },
          prescribedObservers: [],
          prescribedNames: [],
          observations: {
            failureSummaries: [],
            reports: [],
          },
          prescribedObservers: [
            {
              observerAddress: STUB_ADDRESS,
              gatewayAddress: STUB_OPERATOR_ADDRESS,
              stakeWeight: expectedStakeWeight,
              gatewayPerformanceRatio: expectedGatewayPerformanceRatio,
              observerPerformanceRatio: expectedObserverPerformanceRatio,
              compositeWeight: expectedCompositeWeight,
              normalizedCompositeWeight: expectedNormalizedCompositeWeight,
              tenureWeight: expectedTenureWeight,
              stake: updatedOperatorStake,
              startTimestamp: 0,
            },
          ],
          prescribedNames: ['prescribed-name'],
          distributions: {
            totalEligibleGatewayReward: expectedSecondEpochGatewayReward,
            totalEligibleGateways: 1,
            totalEligibleObserverReward: expectedSecondEpochObserverReward,
            totalEligibleRewards: expectedNewEligibleRewards,
          },
        });
        sharedMemory = tickMemory;
      });
    });
    // TODO: add tests to create N epochs
  });
});
