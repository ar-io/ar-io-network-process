import { AOProcess, ARIO, ARIO_DEVNET_PROCESS_ID, Logger } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import { strict as assert } from 'node:assert';
import { describe, it, before, after } from 'node:test';
import { DockerComposeEnvironment, Wait } from 'testcontainers';

// set debug level logs for to get detailed messages
Logger.default.setLogLevel('info');

export const mARIOPerARIO = 1_000_000;
export const ARIOToMARIO = (amount) => amount * mARIOPerARIO;

const processId = process.env.ARIO_NETWORK_PROCESS_ID || ARIO_DEVNET_PROCESS_ID;
const io = ARIO.init({
  process: new AOProcess({
    processId,
    ao: connect({
      CU_URL: 'http://localhost:6363',
    }),
  }),
});

const projectRootPath = process.cwd();

describe('setup', () => {
  let compose;
  before(async () => {
    compose = await new DockerComposeEnvironment(
      projectRootPath,
      'tests/monitor/docker-compose.test.yml',
    )
      .withBuild()
      .withWaitStrategy('ao-cu-1', Wait.forHttp('/', 6363))
      .up(['ao-cu']);
  });

  after(async () => {
    await compose.down();
  });

  describe('handlers', () => {
    it('should always have correct handler order', async () => {
      const { Handlers: handlersList } = await io.getInfo();
      /**
       * There are three patch handlers before _eval and _default
       *
       * {
       *   handle = function: 0xed28f8,
       *   pattern = function: 0xf97130,
       *   name = "_patch_reply"
       * },
       * {
       *   handle = function: 0x912128,
       *   pattern = function: 0xd37708,
       *   name = "Assignment-Check"
       * },
       * {
       *     handle = function: 0x755910,
       *     pattern = function: 0x929600,
       *     name = "sec-patch-6-5-2024"
       * }
       */
      // ensure eval and default are in the list
      assert(
        handlersList.includes('_eval'),
        '_eval handler is not in the process handlers list',
      );
      assert(
        handlersList.includes('_default'),
        '_default handler is not in the process handlers list',
      );
      const evalIndex = handlersList.indexOf('_eval');
      const defaultIndex = handlersList.indexOf('_default');
      const sanitizeIndex = handlersList.indexOf('sanitize');
      const pruneIndex = handlersList.indexOf('prune');
      assert(
        pruneIndex === sanitizeIndex + 1 &&
          sanitizeIndex === defaultIndex + 1 &&
          defaultIndex === evalIndex + 1,
        `Prune index (${pruneIndex}) and sanitize index (${sanitizeIndex}) are not the first and second handlers after _default (${handlersList})`,
      );
    });
  });

  describe('balances', () => {
    it('should always be up to date', async () => {
      const { items: balances } = await io.getBalances({
        limit: 10_000,
      });
      // assert they are all integers
      for (const balance of balances) {
        assert(
          Number.isInteger(balance.balance),
          `Balance for ${balance.address} is not an integer: ${balance.balance}`,
        );
      }
    });

    it('should always be able to fetch the protocol balance and it should be greater than 0', async () => {
      const balance = await io.getBalance({
        address: processId,
      });
      // assert it is greater than 0 and response is a number
      assert(
        balance >= 0 && typeof balance === 'number',
        'Balance is not valid',
      );
    });
  });

  describe('distribution totals', () => {
    it('should always have correct eligible rewards for the current epoch (within 10 mARIO)', async () => {
      const { distributions: currentEpochDistributions } =
        await io.getCurrentEpoch();

      // assert it has eligible rewards
      assert(
        currentEpochDistributions.rewards?.eligible !== undefined,
        'No eligible rewards found for current epoch',
      );

      // No eligible rewards for the current epoch
      if (
        Object.keys(currentEpochDistributions.rewards.eligible).length === 0
      ) {
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
    it('should always be 1 billion ARIO', async () => {
      const supplyData = await io.getTokenSupply();
      assert(
        supplyData.total === ARIOToMARIO(1000000000),
        `Total supply is not 1 billion ARIO: ${supplyData.total}`,
      );
      assert(
        supplyData.protocolBalance > 0,
        `Protocol balance is empty: ${supplyData.protocolBalance}`,
      );
      assert(
        supplyData.circulating >= 0,
        `Circulating supply is undefined: ${supplyData.circulating}`,
      );
      assert(
        supplyData.locked >= 0,
        `Locked supply is undefined: ${supplyData.locked}`,
      );
      assert(
        supplyData.staked >= 0,
        `Staked supply is undefined: ${supplyData.staked}`,
      );
      assert(
        supplyData.withdrawn >= 0,
        `Withdrawn supply is undefined: ${supplyData.withdrawn}`,
      );
      assert(
        supplyData.delegated >= 0,
        `Delegated supply is undefined: ${supplyData.delegated}`,
      );

      const { items: balances } = await io.getBalances({
        limit: 10_000,
      });

      const protocolBalance = await io.getBalance({
        address: processId,
      });

      assert(
        protocolBalance === supplyData.protocolBalance,
        `Protocol balance is not equal to the balance provided by the contract: ${protocolBalance} !== ${supplyData.protocolBalance}`,
      );

      const totalBalances = balances.reduce(
        (acc, curr) => acc + curr.balance,
        0,
      );
      const circulating = totalBalances - protocolBalance;
      assert(
        circulating === supplyData.circulating,
        `Circulating supply is not equal to the sum of the balances minus the protocol balance: ${circulating} !== ${supplyData.circulating}`,
      );

      // get the supply staked
      const { items: gateways } = await io.getGateways({
        limit: 1000,
      });

      const staked = gateways.reduce(
        (acc, curr) => acc + curr.operatorStake,
        0,
      );

      assert(
        staked === supplyData.staked,
        `Staked supply is not equal to the sum of the operator stakes: ${staked} !== ${supplyData.staked}`,
      );

      const delegated = gateways.reduce(
        (acc, curr) => acc + curr.totalDelegatedStake,
        0,
      );

      assert(
        delegated === supplyData.delegated,
        `Delegated supply is not equal to the sum of the total delegated stakes: ${delegated} !== ${supplyData.delegated}`,
      );

      const computedTotal =
        supplyData.circulating +
        supplyData.locked +
        supplyData.withdrawn +
        supplyData.staked +
        supplyData.delegated +
        supplyData.protocolBalance;
      assert(
        supplyData.total === computedTotal &&
          computedTotal === ARIOToMARIO(1000000000),
        `Computed total supply (${computedTotal}) is not equal to the sum of protocol balance, circulating, locked, staked, and delegated and withdrawn provided by the contract (${supplyData.total}) and does not match the expected total of 1 billion ARIO`,
      );

      const computedCirculating =
        supplyData.total -
        supplyData.locked -
        supplyData.staked -
        supplyData.delegated -
        supplyData.withdrawn -
        supplyData.protocolBalance;
      assert(
        supplyData.circulating === computedCirculating,
        `Computed circulating supply (${computedCirculating}) is not equal to the total supply minus protocol balance, locked, staked, delegated, and withdrawn provided by the contract (${supplyData.circulating})`,
      );
    });
  });

  // epoch information
  describe('epoch', () => {
    it('should always be up to date', async () => {
      const { durationMs, epochZeroStartTimestamp } =
        await io.getEpochSettings();
      const currentEpochIndex = Math.floor(
        (Date.now() - epochZeroStartTimestamp) / durationMs,
      );
      const { epochIndex } = await io.getCurrentEpoch();
      assert(
        epochIndex === currentEpochIndex,
        `Epoch index is not up to date: ${epochIndex}`,
      );
    });
    it('should contain the startTimestamp, endTimestamp and distributions and observations for the current epoch', async () => {
      const {
        epochIndex,
        startTimestamp,
        endTimestamp,
        distributions,
        observations,
      } = await io.getCurrentEpoch();
      assert(epochIndex > 0, 'Epoch index is not valid');
      assert(distributions, 'Distributions are not valid');
      assert(observations, 'Observations are not valid');
      assert(
        startTimestamp > 0,
        `Start timestamp is not valid: ${startTimestamp}`,
      );
      assert(
        endTimestamp > startTimestamp,
        `End timestamp is not greater than start timestamp: ${endTimestamp} > ${startTimestamp}`,
      );
      assert(distributions.rewards.eligible, 'Eligible rewards are not valid');

      // compare the current gateway count to the current epoch totalEligibleRewards
      const { items: gateways } = await io.getGateways({
        limit: 1000, // we will need to update this if the number of gateways grows
      });
      const activeGatewayCountForEpoch = gateways.filter(
        (gateway) =>
          gateway.status === 'joined' &&
          gateway.startTimestamp <= startTimestamp,
      ).length;
      assert(
        activeGatewayCountForEpoch === distributions.totalEligibleGateways,
        `Active gateway count (${activeGatewayCountForEpoch}) does not match total eligible gateways (${distributions.totalEligibleGateways}) for the current epoch`,
      );
    });

    it('the previous epoch should have a been distributed', async () => {
      const { epochIndex: currentEpochIndex } = await io.getCurrentEpoch();
      const previousEpochIndex = currentEpochIndex - 1;
      const { epochIndex, distributions, endTimestamp, startTimestamp } =
        await io.getEpoch({ epochIndex: previousEpochIndex });
      assert(
        epochIndex === previousEpochIndex,
        'Previous epoch index is not valid',
      );
      assert(distributions, 'Distributions are not valid');
      assert(
        endTimestamp > startTimestamp,
        'End timestamp is not greater than start timestamp',
      );
      assert(
        distributions.distributedTimestamp >= endTimestamp,
        'Distributed timestamp is not greater than epoch end timestamp',
      );
      assert(
        distributions.rewards.eligible !== undefined,
        'Eligible rewards are not valid',
      );
      // assert all eligible rewards are integers
      assert(
        Object.values(distributions.rewards.eligible).every(
          (reward) =>
            Number.isInteger(reward.operatorReward) &&
            Object.values(reward.delegateRewards).every((delegateReward) =>
              Number.isInteger(delegateReward),
            ),
        ),
        `Eligible rewards for the previous epoch (${previousEpochIndex}) are not integers`,
      );
      assert(
        distributions.rewards.distributed !== undefined,
        'Distributed rewards are not valid',
      );
      // assert distributed rewards are integers
      assert(
        Object.values(distributions.rewards.distributed).every((reward) =>
          Number.isInteger(reward),
        ),
        `Distributed rewards for the previous epoch (${previousEpochIndex}) are not integers`,
      );
    });
  });

  describe('demand factor', () => {
    it('should always be greater than 0.5', async () => {
      const demandFactor = await io.getDemandFactor();
      assert(
        demandFactor >= 0.5,
        `Demand factor is less than 0.5: ${demandFactor}`,
      );
    });
  });

  // gateway registry - ensure no invalid gateways
  describe('gateway registry', () => {
    it('should only have valid gateways', { timeout: 60000 }, async () => {
      const { durationMs, epochZeroStartTimestamp } =
        await io.getEpochSettings();
      // compute the epoch index based on the epoch settings
      const currentEpochIndex = Math.floor(
        (Date.now() - epochZeroStartTimestamp) / durationMs,
      );

      let cursor = undefined;
      let totalGateways = 0;
      const uniqueGateways = new Set();
      do {
        const {
          items: gateways,
          nextCursor,
          totalItems,
        } = await io.getGateways({
          cursor,
        });
        totalGateways = totalItems;
        for (const gateway of gateways) {
          uniqueGateways.add(gateway.gatewayAddress);
          if (gateway.status === 'joined') {
            assert(
              Number.isInteger(gateway.operatorStake),
              `Gateway ${gateway.gatewayAddress} has an invalid operator stake: ${gateway.operatorStake}`,
            );
            assert(
              Number.isInteger(gateway.totalDelegatedStake),
              `Gateway ${gateway.gatewayAddress} has an invalid total delegated stake: ${gateway.totalDelegatedStake}`,
            );
            assert(
              gateway.operatorStake >= 10_000_000_000,
              `Gateway ${gateway.gatewayAddress} has less than 10_000_000_000 ARIO staked`,
            );
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
            assert(gateway.totalDelegatedStake === 0);
            assert(gateway.operatorStake === 0);
          }
        }
        cursor = nextCursor;
      } while (cursor !== undefined);
      assert(
        uniqueGateways.size === totalGateways,
        `Counted total gateways (${uniqueGateways.size}) does not match total gateways (${totalGateways})`,
      );
    });

    it('should have valid delegates for all gateways', async () => {
      const { items: gateways } = await io.getGateways({
        limit: 1000,
      });
      // NOTE: this is an attempt to get the delegates for a gateway, the UX is not great so consider modifying or adding handlers to support gateway specific delegation filters
      for (const gateway of gateways) {
        const { items: delegates } = await io.getGatewayDelegates({
          address: gateway.gatewayAddress,
        });
        if (delegates.length > 0) {
          for (const delegate of delegates) {
            assert(
              delegate.delegatedStake >= 0 && delegate.startTimestamp > 0,
              `Gateway ${gateway.gatewayAddress} has invalid delegate`,
            );
            const { items: allDelegations } = await io.getDelegations({
              address: delegate.address,
              limit: 1000,
            });
            const delegations = allDelegations.filter(
              (delegation) =>
                delegation.gatewayAddress === gateway.gatewayAddress,
            );
            const stakes = delegations.filter(
              (delegation) => delegation.type === 'stake',
            );
            const vaults = delegations.filter(
              (delegation) => delegation.type === 'vault',
            );
            for (const stake of stakes) {
              assert(
                stake.balance >= 0, // can be 0 if the delegate is unstaking
                `Gateway ${gateway.gatewayAddress} has invalid stake for delegate ${delegate.address}: ${stake.balance}`,
              );
              assert(
                stake.startTimestamp > 0,
                `Gateway ${gateway.gatewayAddress} has invalid stake start timestamp for delegate ${delegate.address}: ${stake.startTimestamp}`,
              );
            }
            for (const vault of vaults) {
              assert(
                vault.balance > 0, // should never be zero
                `Gateway ${gateway.gatewayAddress} has invalid vault for delegate ${delegate.address}: ${vault.balance}`,
              );
              assert(
                vault.startTimestamp > 0 &&
                  vault.endTimestamp > vault.startTimestamp,
                `Gateway ${gateway.gatewayAddress} has invalid vault start and end timestamps for delegate ${delegate.address}: ${vault.startTimestamp} and ${vault.endTimestamp}`,
              );
            }
          }
        }
      }
    });

    it('should have valid vaults for all gateways', async () => {
      const { items: gateways } = await io.getGateways({
        limit: 1000,
      });

      for (const gateway of gateways) {
        const { items: vaults } = await io.getGatewayVaults({
          address: gateway.gatewayAddress,
        });
        if (vaults.length === 0) {
          for (const vault of vaults) {
            // assert vault balance is greater than 0 and startTimestamp and endTimestamp are valid timestamps (they are all set to 90 by default, but old ones have to expire out)
            assert(
              Number.isInteger(vault.balance),
              `Vault ${vaultId} on gateway ${gateway.gatewayAddress} has an invalid balance (${vault.balance})`,
            );
            assert(
              vault.balance >= 0,
              `Vault ${vaultId} on gateway ${gateway.gatewayAddress} has an invalid balance (${vault.balance})`,
            );
            assert(
              vault.startTimestamp > 0,
              `Vault ${vaultId} on gateway ${gateway.gatewayAddress} has an invalid start timestamp (${vault.startTimestamp})`,
            );
            assert(
              vault.endTimestamp > 0,
              `Vault ${vault.vaultId} on gateway ${gateway.gatewayAddress} has an invalid end timestamp (${vault.endTimestamp})`,
            );
            assert(
              vault.endTimestamp > vault.startTimestamp,
              `Vault ${vault.vaultId} on gateway ${gateway.gatewayAddress} has an invalid end timestamp (${vault.endTimestamp})`,
            );
          }
        }
      }
    });
  });

  // arns registry - ensure no invalid arns
  describe('arns names', () => {
    const twoWeeks = 2 * 7 * 24 * 60 * 60 * 1000;
    it(
      'should not have any arns records older than two weeks',
      { timeout: 60000 },
      async () => {
        let cursor = undefined;
        let totalArns = 0;
        const uniqueNames = new Set();
        do {
          const {
            items: arns,
            nextCursor,
            totalItems,
          } = await io.getArNSRecords({
            cursor,
          });
          totalArns = totalItems;
          for (const arn of arns) {
            uniqueNames.add(arn.name);
            assert(arn.processId, `ARNs name '${arn.name}' has no processId`);
            assert(arn.type, `ARNs name '${arn.name}' has no type`);
            assert(
              arn.startTimestamp,
              `ARNs name '${arn.name}' has no start timestamp`,
            );
            assert(
              Number.isInteger(arn.purchasePrice) && arn.purchasePrice >= 0,
              `ARNs name '${arn.name}' has invalid purchase price: ${arn.purchasePrice}`,
            );
            assert(
              Number.isInteger(arn.undernameLimit) && arn.undernameLimit >= 10,
              `ARNs name '${arn.name}' has invalid undername limit: ${arn.undernameLimit}`,
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
        assert(
          uniqueNames.size === totalArns,
          `Counted total ARNs (${uniqueNames.size}) does not match total ARNs (${totalArns})`,
        );
      },
    );
  });
});
