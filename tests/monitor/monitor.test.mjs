import { AOProcess, ARIO, ARIO_DEVNET_PROCESS_ID, Logger } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import { strict as assert } from 'node:assert';
import { describe, it, before, after } from 'node:test';
import { DockerComposeEnvironment, Wait } from 'testcontainers';

// set debug level logs for to get detailed messages
Logger.default.setLogLevel('info');

export const mARIOPerARIO = 1_000_000;
export const ARIOToMARIO = (amount) => amount * mARIOPerARIO;

const twoWeeksMs = 2 * 7 * 24 * 60 * 60 * 1000;
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
      .withWaitStrategy('ao-cu', Wait.forHttp(`/state/${processId}`, 6363))
      .up();
  });

  after(async () => {
    await compose.down();
  });

  const getBalances = async () => {
    let cursor;
    let balances = [];
    while (true) {
      const {
        items: balancePage,
        nextCursor,
        hasMore,
      } = await io.getBalances({
        limit: 1_000,
        cursor,
      });
      balances = [...balances, ...balancePage];
      cursor = nextCursor;
      if (!hasMore) {
        break;
      }
    }
    return balances;
  };

  const getGateways = async () => {
    let cursor;
    let gateways = [];
    while (true) {
      const {
        items: gatewaysPage,
        nextCursor,
        hasMore,
      } = await io.getGateways({
        limit: 1000,
        cursor,
      });
      gateways = [...gateways, ...gatewaysPage];
      cursor = nextCursor;
      if (!hasMore) {
        break;
      }
    }
    return gateways;
  };

  const getDelegates = async () => {
    let cursor;
    let delegates = [];
    while (true) {
      const {
        items: delegatesPage,
        nextCursor,
        hasMore,
      } = await io.getAllDelegates({
        limit: 1000,
        cursor,
      });
      delegates = [...delegates, ...delegatesPage];
      cursor = nextCursor;
      if (!hasMore) {
        break;
      }
    }
    return delegates;
  };

  const getGatewayVaults = async () => {
    let cursor;
    let gatewayVaults = [];
    while (true) {
      const {
        items: gatewayVaultsPage,
        nextCursor,
        hasMore,
      } = await io.getAllGatewayVaults({
        limit: 1000,
        cursor,
      });
      gatewayVaults = [...gatewayVaults, ...gatewayVaultsPage];
      cursor = nextCursor;
      if (!hasMore) {
        break;
      }
    }
    return gatewayVaults;
  };

  const getArNSRecords = async () => {
    let cursor;
    let arNSRecords = [];
    while (true) {
      const {
        items: recordsPage,
        nextCursor,
        hasMore,
      } = await io.getArNSRecords({
        limit: 1000,
        cursor,
      });
      arNSRecords = [...arNSRecords, ...recordsPage];
      cursor = nextCursor;
      if (!hasMore) {
        break;
      }
    }
    return arNSRecords;
  };

  const getVaults = async () => {
    let cursor;
    let vaults = [];
    while (true) {
      const {
        items: vaultsPage,
        nextCursor,
        hasMore,
      } = await io.getVaults({
        limit: 1000,
        cursor,
      });
      vaults = [...vaults, ...vaultsPage];
      cursor = nextCursor;
      if (!hasMore) {
        break;
      }
    }
    return vaults;
  };

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
      assert(
        handlersList.includes('sanitize'),
        'sanitize handler is not in the process handlers list',
      );
      assert(
        handlersList.includes('prune'),
        'prune handler is not in the process handlers list',
      );
      const evalIndex = handlersList.indexOf('_eval');
      const sanitizeIndex = handlersList.indexOf('sanitize');
      const pruneIndex = handlersList.indexOf('prune');
      assert(
        evalIndex < sanitizeIndex && sanitizeIndex < pruneIndex,
        `Prune index (${pruneIndex}) and sanitize index (${sanitizeIndex}) are not the first and second handlers after _eval (${handlersList})`,
      );
    });
  });

  describe('balances', () => {
    let balances = [];
    before(async () => {
      balances = await getBalances();
    });
    it('should always be up to date', async () => {
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
    it('should always have correct eligible rewards for the the previous epoch (within 10 mARIO)', async () => {
      const currentEpoch = await io.getCurrentEpoch();
      if (currentEpoch == undefined) {
        return;
      }
      const previousEpoch = await io.getEpoch({
        epochIndex: currentEpoch.epochIndex - 1,
      });
      const { distributions: previousEpochDistributions } = previousEpoch;

      // No eligible rewards for the current epoch
      if (
        Object.keys(previousEpochDistributions.rewards.eligible).length === 0
      ) {
        return;
      }

      // add up all the eligible operators and delegates
      const assignedRewards = Object.values(
        previousEpochDistributions.rewards.eligible,
      ).reduce((acc, curr) => {
        const delegateRewards = Object.values(curr.delegateRewards).reduce(
          (d, c) => d + c,
          0,
        );
        return acc + curr.operatorReward + delegateRewards;
      }, 0);

      // handle any rounding errors
      const roundingError =
        assignedRewards - previousEpochDistributions.totalEligibleRewards;
      // assert total eligible rewards rounding is less than 10
      assert(
        roundingError < 10,
        `Rounding for eligible distributions is too large: ${roundingError}`,
      );

      const distributedRewards = Object.values(
        previousEpochDistributions.rewards.distributed,
      ).reduce((acc, curr) => acc + curr, 0);
      assert(
        distributedRewards ===
          previousEpochDistributions.totalDistributedRewards,
        'Distributed rewards do not match the total distributed rewards',
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

      const balances = await getBalances();

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
      const gateways = await getGateways();

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
  describe('epochs', () => {
    let epochSettings;
    let currentEpoch;
    let gateways;

    before(async () => {
      epochSettings = await io.getEpochSettings();
      currentEpoch = await io.getCurrentEpoch();
      gateways = await getGateways();
    });

    it('should always be up to date', async () => {
      if (Date.now() < epochSettings.epochZeroStartTimestamp) {
        return;
      }
      const { durationMs, epochZeroStartTimestamp } = epochSettings;
      const currentEpochIndex = Math.floor(
        (Date.now() - epochZeroStartTimestamp) / durationMs,
      );
      const { epochIndex } = currentEpoch;
      assert(
        epochIndex === currentEpochIndex,
        `Epoch index is not up to date: ${epochIndex}`,
      );
    });
    it('should contain the startTimestamp, endTimestamp and distributions, observations and correct totals and stats for the current epoch', async () => {
      if (Date.now() < epochSettings.epochZeroStartTimestamp) {
        return;
      }
      const {
        epochIndex,
        startTimestamp,
        endTimestamp,
        distributions,
        observations,
      } = currentEpoch;
      assert(epochIndex >= 0, 'Epoch index is not valid');
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
      assert(
        distributions.totalEligibleGateways > 0,
        'Total eligible gateways are not valid',
      );
      assert(
        distributions.totalEligibleGateways <= gateways.length,
        'Total eligible gateways are greater than the total number of gateways',
      );
      assert(
        distributions.totalEligibleRewards > 0,
        'Total eligible rewards are not valid',
      );
      assert(
        distributions.totalEligibleRewards > 0,
        'Total eligible rewards are not valid',
      );
      assert(
        distributions.totalEligibleGatewayReward > 0,
        'Total eligible gateway reward is not valid',
      );
      assert(
        distributions.totalEligibleObserverReward >= 0,
        `Total eligible observer reward is not valid or is negative: ${distributions.totalEligibleObserverReward}`,
      );
      // compare the current gateway count to the current epoch totalEligibleRewards
      const activeGatewayCountAtBeginningOfEpoch = gateways.filter(
        (gateway) =>
          // gateway joined before epoch started
          (gateway.startTimestamp <= startTimestamp &&
            // gateway is currently active OR was active at the beginning of the epoch but chose to leave during the epoch via Leave-Network
            gateway.status === 'joined') ||
          (gateway.status === 'leaving' &&
            // depending on the time of the distribution/tick, this could be 90 days + a few hours, so add 3 hours to the check
            gateway.endTimestamp >=
              startTimestamp + 90 * 24 * 60 * 60 * 1000 + 3 * 60 * 60 * 1000),
      );
      assert(
        activeGatewayCountAtBeginningOfEpoch.length ===
          distributions.totalEligibleGateways,
        `Active gateway count (${activeGatewayCountAtBeginningOfEpoch.length}) at the beginning of the epoch does not match total eligible gateways (${distributions.totalEligibleGateways}) for the current epoch`,
      );
    });

    it('the previous epoch should have a been distributed', async () => {
      if (Date.now() < epochSettings.epochZeroStartTimestamp) {
        return;
      }
      const { epochIndex: currentEpochIndex } = currentEpoch;
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
    let gateways;

    before(async () => {
      gateways = await getGateways();
    });

    it('should only have valid gateways', { timeout: 60000 }, async () => {
      const { durationMs, epochZeroStartTimestamp } =
        await io.getEpochSettings();
      // compute the epoch index based on the epoch settings
      const currentEpochIndex = Math.max(
        0,
        Math.floor((Date.now() - epochZeroStartTimestamp) / durationMs),
      );

      const uniqueGateways = new Set();
      for (const gateway of gateways) {
        uniqueGateways.add(gateway.gatewayAddress);
        if (gateway.status === 'joined') {
          assert(
            gateway.observerAddress !== undefined &&
              typeof gateway.observerAddress === 'string' &&
              gateway.observerAddress.length > 0,
            `Gateway ${gateway.gatewayAddress} has no observer address`,
          );
          assert(
            gateway.startTimestamp !== undefined &&
              Number.isInteger(gateway.startTimestamp) &&
              gateway.startTimestamp > 0,
            `Gateway ${gateway.gatewayAddress} has an invalid start timestamp: ${gateway.startTimestamp}`,
          );
          assert(
            Number.isInteger(gateway.operatorStake) &&
              gateway.operatorStake >= 0,
            `Gateway ${gateway.gatewayAddress} has an invalid operator stake: ${gateway.operatorStake}`,
          );
          assert(
            Number.isInteger(gateway.totalDelegatedStake) &&
              gateway.totalDelegatedStake >= 0,
            `Gateway ${gateway.gatewayAddress} has an invalid total delegated stake: ${gateway.totalDelegatedStake}`,
          );
          assert(
            gateway.status === 'joined' || gateway.status === 'leaving',
            `Gateway ${gateway.gatewayAddress} has an invalid status: ${gateway.status}`,
          );

          // settings
          assert(
            gateway.settings.fqdn !== undefined &&
              typeof gateway.settings.fqdn === 'string' &&
              gateway.settings.fqdn.length > 0,
            `Gateway ${gateway.gatewayAddress} has invalid fqdn: ${gateway.settings.fqdn}`,
          );
          assert(
            gateway.settings.port !== undefined &&
              typeof gateway.settings.port === 'number' &&
              gateway.settings.port > 0,
            `Gateway ${gateway.gatewayAddress} has invalid port: ${gateway.settings.port}`,
          );
          // note is optional
          if (gateway.settings.note !== undefined) {
            assert(
              typeof gateway.settings.note === 'string' &&
                gateway.settings.note.length > 0,
              `Gateway ${gateway.gatewayAddress} has invalid note: ${gateway.settings.note}`,
            );
          }
          assert(
            gateway.settings.label !== undefined &&
              typeof gateway.settings.label === 'string' &&
              gateway.settings.label.length > 0,
            `Gateway ${gateway.gatewayAddress} has no label`,
          );
          assert(
            gateway.settings.protocol !== undefined &&
              gateway.settings.protocol === 'https',
            `Gateway ${gateway.gatewayAddress} has invalid protocol: ${gateway.settings.protocol}`,
          );
          assert(
            gateway.settings.properties !== undefined &&
              typeof gateway.settings.properties === 'string',
            `Gateway ${gateway.gatewayAddress} has invalid properties: ${gateway.settings.properties}`,
          );
          assert(
            gateway.settings.minDelegatedStake !== undefined &&
              Number.isInteger(gateway.settings.minDelegatedStake) &&
              gateway.settings.minDelegatedStake > 0,
            `Gateway ${gateway.gatewayAddress} has invalid min delegated stake: ${gateway.settings.minDelegatedStake}`,
          );
          assert(
            gateway.settings.allowDelegatedStaking !== undefined &&
              typeof gateway.settings.allowDelegatedStaking === 'boolean',
            `Gateway ${gateway.gatewayAddress} has invalid allow delegated staking: ${gateway.settings.allowDelegatedStaking}`,
          );
          assert(
            gateway.settings.delegateRewardShareRatio !== undefined &&
              Number.isInteger(gateway.settings.delegateRewardShareRatio) &&
              gateway.settings.delegateRewardShareRatio >= 0 &&
              gateway.settings.delegateRewardShareRatio <= 95,
            `Gateway ${gateway.gatewayAddress} has invalid delegate reward share ratio: ${gateway.settings.delegateRewardShareRatio}`,
          );
          assert(
            gateway.settings.autoStake !== undefined &&
              typeof gateway.settings.autoStake === 'boolean',
            `Gateway ${gateway.gatewayAddress} has invalid auto stake: ${gateway.settings.autoStake}`,
          );

          // stats
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
      assert(
        uniqueGateways.size === gateways.length,
        `Counted total gateways (${uniqueGateways.size}) does not match total gateways (${gateways.length})`,
      );
    });

    it('should have the correct totalDelegatedStake for every gateway', async () => {
      const allDelegates = await getDelegates();
      for (const gateway of gateways) {
        const filteredForGateway = allDelegates.filter(
          (delegate) => delegate.gatewayAddress === gateway.gatewayAddress,
        );
        const totalDelegatedStake = filteredForGateway.reduce(
          (acc, delegate) => acc + delegate.delegatedStake,
          0,
        );
        assert(
          totalDelegatedStake === gateway.totalDelegatedStake,
          `Gateway ${gateway.gatewayAddress} has an invalid total delegated stake: ${gateway.totalDelegatedStake}`,
        );
      }
    });

    it('should have valid delegates for all gateways', async () => {
      const delegates = await getDelegates();
      for (const delegate of delegates) {
        assert(
          delegate.delegatedStake >= 0 && delegate.startTimestamp > 0,
          `Gateway ${delegate.gatewayAddress} has invalid delegate`,
        );
        // TODO: assert it's a valid gateway that is active
        assert(delegate.gatewayAddress, 'Gateway address is invalid');
        assert(delegate.vaultedStake >= 0, 'Vaulted stake is invalid');
      }
    });

    it('should have valid vaults for all gateways', async () => {
      const vaults = await getGatewayVaults();
      if (vaults.length > 0) {
        for (const vault of vaults) {
          assert(
            Number.isInteger(vault.balance),
            `Vault ${vault.vaultId} on gateway ${vault.gatewayAddress} has an invalid balance (${vault.balance})`, // Fixed vaultId reference
          );
          assert(
            vault.balance >= 0 &&
              vault.balance <= ARIOToMARIO(1_000_000_000_000),
            `Vault ${vault.vaultId} on gateway ${vault.gatewayAddress} has an invalid balance (${vault.balance})`, // Fixed vaultId reference
          );
          assert(
            vault.startTimestamp > 0,
            `Vault ${vault.vaultId} on gateway ${vault.gatewayAddress} has an invalid start timestamp (${vault.startTimestamp})`, // Fixed vaultId reference
          );
          assert(
            vault.endTimestamp > 0,
            `Vault ${vault.vaultId} on gateway ${vault.gatewayAddress} has an invalid end timestamp (${vault.endTimestamp})`,
          );
          assert(
            vault.endTimestamp > vault.startTimestamp,
            `Vault ${vault.vaultId} on gateway ${vault.gatewayAddress} has an invalid end timestamp (${vault.endTimestamp})`,
          );
        }
      }
    });
  });

  describe('vaults', () => {
    const minLockTimeMs = 14 * 24 * 60 * 60 * 1000;
    const maxLockTimeMs = 12 * 365 * 24 * 60 * 60 * 1000;
    it('should have valid vaults with non-zero balance and startTimestamp and endTimestamp', async () => {
      const vaults = await getVaults();
      for (const vault of vaults) {
        assert(
          vault.address,
          `Vault ${vault.vaultId} for ${vaults.address} has no address`,
        );
        assert(
          typeof vault.vaultId === 'string',
          `Vault ${vault.vaultId} for ${vault.address} has an invalid vaultId (${vault.vaultId})`,
        );
        assert(
          vault.balance > 0,
          `Vault ${vault.vaultId} for ${vault.address} has an invalid balance (${vault.balance})`,
        );
        assert(
          vault.startTimestamp <= Date.now(),
          `Vault ${vault.vaultId} for ${vault.address} has an invalid start timestamp ${vault.startTimestamp} (${new Date(vault.startTimestamp).toLocaleString()})`,
        );
        assert(
          vault.endTimestamp > vault.startTimestamp &&
            vault.endTimestamp > Date.now() &&
            vault.endTimestamp >= vault.startTimestamp + minLockTimeMs &&
            vault.endTimestamp <= vault.startTimestamp + maxLockTimeMs &&
            `Vault ${vault.vaultId} for ${vault.address} has an invalid end timestamp ${vault.endTimestamp} (${new Date(vault.endTimestamp).toLocaleString()} - and length of ${
              (vault.endTimestamp - vault.startTimestamp) /
              (24 * 60 * 60 * 1000)
            } days)`,
        );
        if (vault.controller) {
          assert(
            typeof vault.controller === 'string' && vault.controller.length > 0,
            `Vault ${vault.vaultId} on gateway ${vault.gatewayAddress} has an invalid controller (${vault.controller})`,
          );
        }
      }
    });
  });

  // arns registry - ensure no invalid arns
  describe('arns names', () => {
    it(
      'should not have any arns records older than two weeks',
      { timeout: 60000 },
      async () => {
        const arnsRecords = await getArNSRecords();
        const totalArNSRecords = arnsRecords.length;
        const uniqueNames = new Set();
        for (const arn of arnsRecords) {
          uniqueNames.add(arn.name);
          assert(arn.processId, `ArNS name '${arn.name}' has no processId`);
          assert(arn.type, `ArNS name '${arn.name}' has no type`);
          assert(
            arn.startTimestamp,
            `ArNS name '${arn.name}' has no start timestamp`,
          );
          assert(
            Number.isInteger(arn.purchasePrice) && arn.purchasePrice >= 0,
            `ArNS name '${arn.name}' has invalid purchase price: ${arn.purchasePrice}`,
          );
          assert(
            Number.isInteger(arn.undernameLimit) && arn.undernameLimit >= 10,
            `ArNS name '${arn.name}' has invalid undername limit: ${arn.undernameLimit}`,
          );
          if (arn.type === 'lease') {
            assert(
              arn.endTimestamp,
              `ArNS name '${arn.name}' has no end timestamp`,
            );
            assert(
              arn.endTimestamp > Date.now() - twoWeeksMs,
              `ArNS name '${arn.name}' is older than two weeks`,
            );
          }
          // if permabuy, assert no endTimestamp
          if (arn.type === 'permabuy') {
            assert(
              !arn.endTimestamp,
              `ArNS name '${arn.name}' has an end timestamp but is a permabuy`,
            );
          }
        }
        assert(
          uniqueNames.size === totalArNSRecords,
          `Counted total ArNS (${uniqueNames.size}) does not match total ArNS (${totalArNSRecords})`,
        );
      },
    );

    it('should not have any returned names older than two weeks', async () => {
      const twoWeeksMs = 2 * 7 * 24 * 60 * 60 * 1000;
      const { items: returnedNames } = await io.getArNSReturnedNames({
        limit: 1000,
      });
      for (const returnedName of returnedNames) {
        assert(returnedName.name, 'Returned name has no name');
        assert(
          returnedName.startTimestamp &&
            returnedName.startTimestamp <= Date.now(),
          `Returned name ${returnedName.name} has unexpected start timestamp ${returnedName.startTimestamp} (${new Date(returnedName.startTimestamp).toLocaleString()})`,
        );
        assert(
          returnedName.endTimestamp &&
            returnedName.endTimestamp > Date.now() &&
            returnedName.endTimestamp ==
              returnedName.startTimestamp + twoWeeksMs,
          `Returned name ${returnedName.name} has unexpected end timestamp ${returnedName.endTimestamp} (${new Date(returnedName.endTimestamp).toLocaleString()})`,
        );
        assert(
          returnedName.initiator &&
            typeof returnedName.initiator === 'string' &&
            returnedName.initiator.length > 0,
          `Returned name ${returnedName.name} has no initiator`,
        );
      }
    });

    it('should not have any expired reserved names', async () => {
      const { items: reservedNames } = await io.getArNSReservedNames({
        limit: 1000,
      });
      for (const reservedName of reservedNames) {
        assert(reservedName.name, 'Reserved name has no name');
        if (reservedName.endTimestamp) {
          assert(
            reservedName.endTimestamp > Date.now(),
            `Reserved name ${reservedName.name} has unexpected end timestamp ${reservedName.endTimestamp} (${new Date(reservedName.endTimestamp).toLocaleString()})`,
          );
        }
        if (reservedName.target) {
          assert(
            typeof reservedName.target === 'string' &&
              reservedName.target.length > 0,
            `Reserved name ${reservedName.name} has invalid target: ${reservedName.target}`,
          );
        }
      }
    });
  });

  describe('primary name', () => {
    it('should not have any expired primary name requests', async () => {
      const { items: primaryNameRequests } = await io.getPrimaryNameRequests({
        limit: 1000,
      });
      for (const primaryNameRequest of primaryNameRequests) {
        assert(primaryNameRequest.name, 'Primary name request has no name');
        assert(
          primaryNameRequest.startTimestamp &&
            primaryNameRequest.startTimestamp <= Date.now(),
          `Primary name request ${primaryNameRequest.name} has unexpected start timestamp ${primaryNameRequest.startTimestamp} (${new Date(primaryNameRequest.startTimestamp).toLocaleString()})`,
        );
        assert(
          primaryNameRequest.startTimestamp + twoWeeksMs > Date.now(),
          `Primary name request ${primaryNameRequest.name} has unexpected start timestamp ${primaryNameRequest.startTimestamp} (${new Date(primaryNameRequest.startTimestamp).toLocaleString()})`,
        );
      }
    });

    it('should have valid owner and name for every primary name', async () => {
      const { items: primaryNames } = await io.getPrimaryNames({
        limit: 1000,
      });
      for (const primaryName of primaryNames) {
        // assert the base name is a valid arns name
        const baseName = primaryName.name.split('_').pop(); // get the last part of the name
        const record = await io.getArNSRecord({
          name: baseName,
        });
        if (record.type === 'lease') {
          assert(
            record.endTimestamp + twoWeeksMs > Date.now(),
            `Primary name ${primaryName.name} base name of ${baseName} has expired (including grace period)`,
          );
        }
        assert(record, `Primary name ${primaryName.name} has no record`);
        assert(primaryName.owner, 'Primary name has no owner');
        assert(primaryName.name, 'Primary name has no name');
        assert(
          primaryName.startTimestamp,
          'Primary name has no start timestamp',
        );
        assert(primaryName.processId, 'Primary name has no processId');
      }
    });
  });
});
