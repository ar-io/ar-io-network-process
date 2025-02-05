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
  getGateways,
} from './helpers.mjs';
import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import {
  INITIAL_OPERATOR_STAKE,
  STUB_ADDRESS,
  STUB_HASH_CHAIN,
  STUB_OPERATOR_ADDRESS,
  STUB_TIMESTAMP,
} from '../tools/constants.mjs';

describe('epochs', () => {
  let sharedMemory;
  let firstEpoch;
  let secondEpoch;
  let epochSettings;

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

      it('should create the first epoch at epoch zero start timestamp', async () => {
        const { memory: tickMemory } = await tick({
          memory: sharedMemory,
          timestamp: epochSettings.epochZeroStartTimestamp,
        });
        const epoch = await getEpoch({
          memory: tickMemory,
          timestamp: epochSettings.epochZeroStartTimestamp,
        });
        assert.deepStrictEqual(epoch, {
          epochIndex: 0,
          startTimestamp: epochSettings.epochZeroStartTimestamp,
          endTimestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
          startHeight: 1,
          distributionTimestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.durationMs +
            epochSettings.distributionDelayMs,
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
          distributions: [], // TODO: ideally this is encoded as an empty object, consider adding a helper function to encode empty objects
        });
        firstEpoch = epoch;
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
    });

    describe('Prescribe Current Epoch', () => {
      it('should prescribe the first epoch after the distribution delay', async () => {
        const { memory: tickMemory } = await tick({
          memory: sharedMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.distributionDelayMs,
        });
        const epoch = await getEpoch({
          memory: tickMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.distributionDelayMs,
        });
        assert.deepStrictEqual(epoch, {
          ...firstEpoch,
          hashchain: STUB_HASH_CHAIN,
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
            totalEligibleGatewayReward: 22500900000,
            totalEligibleGateways: 1,
            totalEligibleObserverReward: 2500100000,
            totalEligibleRewards: 25001000000,
            rewards: {
              eligible: {
                [STUB_OPERATOR_ADDRESS]: {
                  delegateRewards: [],
                  operatorReward: 25001000000, // 0.001 of the protocol balance after the transfers and name purchase
                },
              },
            },
          },
        });
        firstEpoch = epoch;
        sharedMemory = tickMemory;
      });

      it('should return the prescribed observers for the current epoch with weights', async () => {
        const prescribedObservers = await getPrescribedObservers({
          memory: sharedMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.distributionDelayMs,
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
          timestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.distributionDelayMs,
        });
        assert.deepStrictEqual(prescribedNames, ['prescribed-name']);
      });
    });

    describe('Create Next Epoch', () => {
      it('should create the next epoch at the next epoch start timestamp', async () => {
        const { memory: tickMemory } = await tick({
          memory: sharedMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
          blockHeight: 2, // for the next epoch, the block height is 2 (this is usually provided by the MU)
        });
        const epoch = await getEpoch({
          memory: tickMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
        });
        assert.deepStrictEqual(epoch, {
          epochIndex: 1,
          startTimestamp:
            epochSettings.epochZeroStartTimestamp + epochSettings.durationMs,
          endTimestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.durationMs * 2,
          startHeight: 2,
          distributionTimestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.durationMs * 2 +
            epochSettings.distributionDelayMs,
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
          distributions: [], // TODO: ideally this is encoded as an empty object, consider adding a helper function to encode empty objects
        });
        secondEpoch = epoch;
        sharedMemory = tickMemory;
      });
    });

    describe('Distribute First Epoch', () => {
      it('should distribute the first epoch and remove it from state at the next epoch distribution timestamp', async () => {
        const { memory: tickMemory, result: tickResult } = await tick({
          memory: sharedMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.durationMs +
            epochSettings.distributionDelayMs,
        });

        const epochDistributionMessage = tickResult.Messages.find(
          (m) =>
            m.Tags.find((t) => t.name === 'Action').value ===
            'Epoch-Distribution-Notice',
        );
        const epochDistributionData = JSON.parse(epochDistributionMessage.Data);
        assert.deepStrictEqual(
          {
            ...firstEpoch,
            distributions: {
              ...firstEpoch.distributions,
              distributedTimestamp:
                epochSettings.epochZeroStartTimestamp +
                epochSettings.durationMs +
                epochSettings.distributionDelayMs,
              totalDistributedRewards: 16875675000,
              rewards: {
                ...firstEpoch.distributions.rewards,
                distributed: {
                  [STUB_OPERATOR_ADDRESS]: 16875675000, // received the full operator reward, but docked 25% for not observing
                },
              },
            },
          },
          epochDistributionData,
        );
        const epoch = await getEpoch({
          memory: tickMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.durationMs +
            epochSettings.distributionDelayMs,
          epochIndex: 0,
        });
        assert.deepStrictEqual(epoch, null);
        sharedMemory = tickMemory;
      });

      it('should prescribe the second epoch once the first has been distributed, using updated weights for the prescribed observers', async () => {
        const newEpoch = await getEpoch({
          memory: sharedMemory,
          timestamp:
            epochSettings.epochZeroStartTimestamp +
            epochSettings.durationMs +
            epochSettings.distributionDelayMs,
          epochIndex: 1,
        });
        assert.deepStrictEqual(newEpoch, {
          ...secondEpoch,
          hashchain: STUB_HASH_CHAIN,
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
              stake: INITIAL_OPERATOR_STAKE + 16875675000, // includes the new reward from the previous epoch
              startTimestamp: 0,
            },
          ],
          prescribedNames: ['prescribed-name'],
          distributions: {
            totalEligibleGatewayReward: 22493305945,
            totalEligibleGateways: 1,
            totalEligibleObserverReward: 2499256216,
            totalEligibleRewards: 24992562162,
            rewards: {
              eligible: {
                [STUB_OPERATOR_ADDRESS]: {
                  delegateRewards: [],
                  operatorReward: 24992562161, // 0.001 of the protocol balance after the transfers and name purchase
                },
              },
            },
          },
        });
      });
    });
  });
});
