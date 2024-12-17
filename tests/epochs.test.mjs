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
} from './helpers.mjs';
import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import { STUB_ADDRESS, STUB_OPERATOR_ADDRESS } from '../tools/constants.mjs';

const firstEpochStartTimestamp = 1719900000000;
const epochLength = 1000 * 60 * 60 * 24; // 24 hours
const distributionDelay = 1000 * 60 * 40; // 40 minutes

describe('epochs', () => {
  let sharedMemory;

  before(async () => {
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    // have a gateway join, and add an arns name which will be used to prescribe names and observers
    const { memory: gatewayJoinMemory } = await joinNetwork({
      memory: totalTokenSupplyMemory,
      address: STUB_OPERATOR_ADDRESS,
    });
    const { memory: buyRecordMemory } = await buyRecord({
      memory: gatewayJoinMemory,
      name: 'prescribed-name',
      type: 'permabuy',
      from: STUB_OPERATOR_ADDRESS,
    });
    const { memory: tickMemory } = await tick({
      memory: buyRecordMemory,
      timestamp: firstEpochStartTimestamp,
    });
    sharedMemory = tickMemory;
  });

  describe('Epoch', () => {
    it('should return the current epoch', async () => {
      const epoch = await getEpoch({
        memory: sharedMemory,
        timestamp: firstEpochStartTimestamp,
      });
      assert.ok(epoch);
      assert.deepStrictEqual(epoch, {
        epochIndex: 0,
        startTimestamp: firstEpochStartTimestamp,
        endTimestamp: firstEpochStartTimestamp + epochLength,
        startHeight: 1,
        distributionTimestamp:
          firstEpochStartTimestamp + epochLength + distributionDelay,
        prescribedObservers: {
          [STUB_ADDRESS]: STUB_OPERATOR_ADDRESS,
        },
        prescribedNames: ['prescribed-name'],
        observations: {
          failureSummaries: [],
          reports: [],
        },
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
    });
  });

  describe('Prescribed Observers', () => {
    it('should return the correct epoch for the current epoch with weights', async () => {
      const prescribedObservers = await getPrescribedObservers({
        memory: sharedMemory,
        timestamp: firstEpochStartTimestamp,
      });
      assert.ok(prescribedObservers);
      assert.deepStrictEqual(prescribedObservers, [
        {
          compositeWeight: 4,
          gatewayAddress: STUB_OPERATOR_ADDRESS,
          gatewayRewardRatioWeight: 1,
          normalizedCompositeWeight: 1,
          observerAddress: STUB_ADDRESS,
          observerRewardRatioWeight: 1,
          stakeWeight: 1,
          tenureWeight: 4,
        },
      ]);
    });
  });

  describe('Prescribed Names', () => {
    it('should return the correct epoch for the first epoch', async () => {
      const prescribedNames = await getPrescribedNames({
        memory: sharedMemory,
        timestamp: firstEpochStartTimestamp,
      });
      assert.ok(prescribedNames);
      assert.deepStrictEqual(prescribedNames, ['prescribed-name']);
    });
  });

  describe('Epoch-Settings', () => {
    it('should return the correct epoch settings', async () => {
      const epochSettings = await getEpochSettings({
        memory: sharedMemory,
        timestamp: firstEpochStartTimestamp,
      });
      assert.ok(epochSettings);
      assert.deepStrictEqual(epochSettings, {
        maxObservers: 50,
        epochZeroStartTimestamp: firstEpochStartTimestamp,
        durationMs: epochLength,
        distributionDelayMs: distributionDelay,
        prescribedNameCount: 2,
        pruneEpochsCount: 14,
      });
    });
  });
});
