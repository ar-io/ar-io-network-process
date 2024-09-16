import { AOProcess, IO, IO_TESTNET_PROCESS_ID } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';

const io = IO.init({
  process: new AOProcess({
    processId: process.env.IO_PROCESS_ID || IO_TESTNET_PROCESS_ID,
    ao: connect({
      CU_URL: process.env.AO_CU_URL || 'https://cu.ar-io.dev',
    }),
  }),
});

describe('distribution totals', () => {
  it('should always have correct eligible rewards for the current epoch (within 10 mIO)', async () => {
    const { distributions: currentEpochDistributions } =
      await io.getCurrentEpoch();

    // assert it has eligible rewards
    assert(
      currentEpochDistributions.rewards?.eligible !== undefined,
      'No eligible rewards found for current epoch',
    );

    // TODO: for now pass if distributions are empty
    if (Object.keys(currentEpochDistributions.rewards.eligible).length === 0) {
      return;
    }

    // add up all the eligible operators and delegates
    const assignedRewards = Object.values(
      currentEpochDistributions.rewards.eligible,
    ).reduce((acc, curr) => {
      const delegateRewards = Object.values(curr.delegateRewards).reduce(
        (d, c) => d + c,
        0,
      );
      return acc + curr.operatorReward + delegateRewards;
    }, 0);

    // handle any rounding errors
    const roundingError =
      assignedRewards - currentEpochDistributions.totalEligibleRewards;
    // assert total eligible rewards rounding is less than 10
    assert(
      roundingError < 10,
      `Rounding for eligible distributions is too large: ${roundingError}`,
    );
  });
});

describe('token supply', () => {
  it('should always be 1 billion IO', async () => {
    const totalSupply = await io.getTokenSupply();
    assert(
      totalSupply === 1000000000 * 1000000,
      `Total supply is not 1 billion IO: ${totalSupply}`,
    );
  });
});

// epoch information
describe('epoch', () => {
  it('should always be up to date', async () => {
    const { durationMs, epochZeroStartTimestamp } = await io.getEpochSettings();
    const currentEpochIndex = Math.floor(
      (Date.now() - epochZeroStartTimestamp) / durationMs,
    );
    const { epochIndex } = await io.getCurrentEpoch();
    assert(
      epochIndex === currentEpochIndex,
      `Epoch index is not up to date: ${epochIndex}`,
    );
  });
});

// TODO: add demand factor tests

// gateway registry - ensure no invalid gateways
describe('gateway registry', () => {
  it('should only have valid gateways', async () => {
    const { durationMs, epochZeroStartTimestamp } = await io.getEpochSettings();
    // compute the epoch index based on the epoch settings
    const currentEpochIndex = Math.floor(
      (Date.now() - epochZeroStartTimestamp) / durationMs,
    );

    let cursor = '';
    do {
      const { items: gateways, nextCursor } = await io.getGateways({
        cursor,
      });
      for (const gateway of gateways) {
        if (gateway.status === 'joined') {
          assert(gateway.operatorStake >= 50_000_000_000);
          assert(
            gateway.stats.failedConsecutiveEpochs >= 0,
            `Gateway ${gateway.gatewayAddress} has less than 0 failed consecutive epochs`,
          );
          assert(
            gateway.stats.failedConsecutiveEpochs < 30,
            `Gateway ${gateway.gatewayAddress} has more than 30 failed consecutive epochs`,
          );
          assert(
            gateway.stats.passedConsecutiveEpochs <= currentEpochIndex,
            `Gateway ${gateway.gatewayAddress} has more passed consecutive epochs than current epoch index`,
          );
          assert(
            gateway.stats.passedConsecutiveEpochs >= 0,
            `Gateway ${gateway.gatewayAddress} has less than 0 passed consecutive epochs`,
          );
          assert(
            gateway.stats.totalEpochCount <= currentEpochIndex,
            `Gateway ${gateway.gatewayAddress} has more total epochs than current epoch index`,
          );
          assert(
            gateway.stats.totalEpochCount >= 0,
            `Gateway ${gateway.gatewayAddress} has less than 0 total epochs`,
          );
          assert(
            gateway.stats.prescribedEpochCount <= currentEpochIndex,
            `Gateway ${gateway.gatewayAddress} has more prescribed epochs than current epoch index`,
          );
          assert(
            gateway.stats.prescribedEpochCount >= 0,
            `Gateway ${gateway.gatewayAddress} has less than 0 prescribed epochs`,
          );
        }
        if (gateway.status === 'leaving') {
          assert(gateway.operatorStake === 0);
          assert(
            gateway.vaults[gateway.gatewayAddress].balance >= 50_000_000_000,
            `Gateway ${gateway.gatewayAddress} is leaving with less than 50_000_000 IO`,
          );
        }
      }
      cursor = nextCursor;
    } while (cursor !== undefined);
  });
});

// arns registry - ensure no invalid arns
describe('arns names', () => {
  const twoWeeks = 2 * 7 * 24 * 60 * 60 * 1000;
  it('should not have any arns records older than two weeks', async () => {
    let cursor = '';
    do {
      const { items: arns, nextCursor } = await io.getArNSRecords({
        cursor,
      });
      for (const arn of arns) {
        assert(arn.processId, `ARNs name '${arn.name}' has no processId`);
        assert(arn.type, `ARNs name '${arn.name}' has no type`);
        assert(
          arn.startTimestamp,
          `ARNs name '${arn.name}' has no start timestamp`,
        );
        assert(
          arn.purchasePrice >= 0,
          `ARNs name '${arn.name}' has no purchase price`,
        );
        assert(
          arn.undernameLimit >= 10,
          `ARNs name '${arn.name}' has no undername limit`,
        );
        if (arns.type === 'lease') {
          assert(
            arn.endTimestamp,
            `ARNs name '${arn.name}' has no end timestamp`,
          );
          assert(
            arn.endTimestamp > Date.now() - twoWeeks,
            `ARNs name '${arn.name}' is older than two weeks`,
          );
        }
        // if permabuy, assert no endTimestamp
        if (arn.type === 'permabuy') {
          assert(
            !arn.endTimestamp,
            `ARNs name '${arn.name}' has an end timestamp`,
          );
        }
      }
      cursor = nextCursor;
    } while (cursor !== undefined);
  });
});
