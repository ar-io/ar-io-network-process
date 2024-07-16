const { IOToken, IO, mIOToken } = require('@ar.io/sdk');

const ioContract = IO.init();
const assert = require('node:assert');

(async () => {
  try {
    let totalDifference = 0;
    let totalRewards = 0;
    const currentEpoch = await ioContract.getCurrentEpoch();
    const lastEpochDistribution = await ioContract.getEpoch({
      epochIndex: currentEpoch.epochIndex - 1,
    });
    if (lastEpochDistribution.distributions.rewards) {
      for (const reward of Object.values(
        lastEpochDistribution.distributions.rewards || {},
      )) {
        totalRewards += reward;
      }
      totalDifference +=
        lastEpochDistribution.distributions.totalDistributedRewards -
        totalRewards;
    }
    assert(
      totalDifference === 0,
      'Total distributed rewards mismatch. Expected: 0, got: ' +
        totalDifference,
    );

    console.log('Total distributed rewards for last epoch: ', {
      epochIndex: lastEpochDistribution.epochIndex,
      totalDistributedRewards:
        lastEpochDistribution.distributions.totalDistributedRewards,
    });

    // get the total supply
    const totalSupply = await ioContract.getTokenSupply();
    const expectedTotalSupply = new IOToken(1_000_000_000).toMIO().valueOf();
    assert(
      totalSupply === expectedTotalSupply,
      'Total supply mismatch. Expected: ' +
        expectedTotalSupply +
        ', got: ' +
        totalSupply,
    );
    console.log(
      `Total token supply: ${new mIOToken(totalSupply).toIO().valueOf()} IO`,
    );
  } catch (error) {
    console.error('Assertion failed:', error.message);
    process.exit(1);
  }
})();
