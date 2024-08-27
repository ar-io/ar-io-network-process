import { IO, IO_TESTNET_PROCESS_ID } from '@ar.io/sdk';
import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';

const io = IO.init({
  processId: process.env.IO_PROCESS_ID || IO_TESTNET_PROCESS_ID,
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

// TODO: arns - ensure no invalid arns names

describe('gateway registry', () => {
  it('should only have valid gateways', async () => {
    let cursor = '';
    do {
      const { items: gateways, nextCursor } = await io.getGateways({
        cursor,
      });
      for (const gateway of gateways) {
        assert(gateway.operatorStake >= 50_000_000_000);
      }
      cursor = nextCursor;
    } while (cursor !== undefined);
  });
});

// Gateway registry - ensure no invalid gateways
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
