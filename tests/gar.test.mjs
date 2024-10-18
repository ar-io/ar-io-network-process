import { createAosLoader } from './utils.mjs';
import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  validGatewayTags,
} from '../tools/constants.mjs';

const stubbedTimestamp = 1714857600000;
describe('GatewayRegistry', async () => {
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

  // Helper function to ensure all tags are in an array format
  function normalizeTags(tags) {
    return Array.isArray(tags) ? tags : [tags];
  }

  describe('Join-Network', () => {
    it('should allow joining of the network without services and bundlers', async () => {
      const joinNetworkResult = await handle({
        Tags: validGatewayTags,
      });

      const joinNetworkData = JSON.parse(joinNetworkResult.Messages[0].Data);
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
      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 50_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: joinNetworkData.startTimestamp,
        settings: {
          label: 'test-gateway',
          note: 'test-note',
          fqdn: 'test-fqdn',
          port: 443,
          protocol: 'https',
          allowDelegatedStaking: true,
          minDelegatedStake: 500_000_000,
          delegateRewardShareRatio: 0,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          autoStake: true,
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
      });
    });

    it('should allow joining of the network with valid services and bundlers', async () => {
      const validGatewayTagsWithServices = [
        ...validGatewayTags,
        {
          name: 'Services',
          value: JSON.stringify({
            bundlers: [
              {
                fqdn: 'bundler1.example.com',
                port: 443,
                protocol: 'https',
                path: '/bundler1',
              },
              {
                fqdn: 'bundler2.example.com',
                port: 443,
                protocol: 'https',
                path: '/',
              },
            ],
          }),
        },
      ];

      const joinNetworkResult = await handle({
        Tags: validGatewayTagsWithServices,
      });

      const joinNetworkData = JSON.parse(joinNetworkResult.Messages[0].Data);
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
      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 50_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: joinNetworkData.startTimestamp,
        settings: {
          label: 'test-gateway',
          note: 'test-note',
          fqdn: 'test-fqdn',
          port: 443,
          protocol: 'https',
          allowDelegatedStaking: true,
          minDelegatedStake: 500_000_000,
          delegateRewardShareRatio: 0,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          autoStake: true,
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
        services: {
          bundlers: [
            {
              fqdn: 'bundler1.example.com',
              port: 443,
              protocol: 'https',
              path: '/bundler1',
            },
            {
              fqdn: 'bundler2.example.com',
              port: 443,
              protocol: 'https',
              path: '/',
            },
          ],
        },
      });
    });

    // bad inputs
    const badInputTags = [
      // invalid observer
      [{ name: 'Observer-Address', value: 'invalid-arweave-address' }],
      // invalid stake
      [{ name: 'Operator-Stake', value: '49999999999' }], // one less than the minimum
      // invalid port
      [{ name: 'Port', value: '65536' }],
      // invalid protocol
      [{ name: 'Protocol', value: 'http' }],
      // invalid min-delegated-stake
      [{ name: 'Min-Delegated-Stake', value: '499999999' }],
      // invalid properties
      [{ name: 'Properties', value: 'invalid' }],
      // improperly formatted services
      [{ name: 'Services', value: 'not-json' }],
      // incorrect structure within services
      {
        name: 'Services',
        value: JSON.stringify({
          bundlers: 'incorrect-string', // Should be an array, not a string
        }),
      },
      {
        name: 'Services',
        value: JSON.stringify({
          bundlers: [
            {
              port: 443,
              protocol: 'https',
              path: '/bundler1', // Missing `fqdn`
            },
          ],
        }),
      },
      {
        name: 'Services',
        value: JSON.stringify({
          bundlers: [
            {
              fqdn: 'bundler1.example.com',
              port: '443', // Incorrect data type for port
              protocol: 'https',
              path: '/bundler1',
            },
          ],
        }),
      },
      {
        name: 'Services',
        value: JSON.stringify({
          bundlers: [
            {
              fqdn: 'bundler1.example.com',
              port: 443,
              protocol: 'ftp', // Unsupported protocol
              path: '/bundler1',
            },
          ],
        }),
      },
      {
        name: 'Services',
        value: JSON.stringify({
          bundlers: [
            {
              fqdn: 'bundler1.example.com',
              port: 443,
              protocol: 'https',
              path: '/bundler1',
              details: { active: true }, // Unexpected nested object
            },
          ],
        }),
      },
    ];
    // Iterate over each set of bad input tags
    badInputTags.forEach((tags) => {
      const normalizedTags = normalizeTags(tags); // Ensure tags are always arrays

      it(`should fail to join the network with bad input: ${JSON.stringify(normalizedTags)}`, async () => {
        // Filter out tags from validGatewayTags that are overridden by normalizedTags
        const overwriteTags = validGatewayTags.filter(
          (vTag) => !normalizedTags.some((t) => t.name === vTag.name),
        );

        const joinNetworkResult = await handle({
          Tags: [...overwriteTags, ...normalizedTags],
        });

        // Confirm there is an error tag
        const errorTag = joinNetworkResult.Messages[0].Tags.find(
          (tag) => tag.name === 'Error',
        );
        assert(errorTag, 'Error tag not found');

        // Confirm gateway did not join
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

        // Assert gateway data does not exist
        assert.equal(gatewayData, null);
      });
    });
  });

  describe('Update-Gateway-Settings', () => {
    it('should allow updating the gateway settings', async () => {
      const joinNetworkResult = await handle({
        Tags: validGatewayTags,
      });

      const joinNetworkData = JSON.parse(joinNetworkResult.Messages[0].Data);

      const updateGatewaySettingsResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Update-Gateway-Settings' },
            { name: 'Label', value: 'new-label' },
            { name: 'Note', value: 'new-note' },
            { name: 'FQDN', value: 'new-fqdn' },
            { name: 'Port', value: '80' },
            { name: 'Protocol', value: 'https' },
            { name: 'Allow-Delegated-Staking', value: 'false' },
            { name: 'Min-Delegated-Stake', value: '1000000000' }, // 1K IO
            { name: 'Delegate-Reward-Share-Ratio', value: '10' },
            {
              name: 'Properties',
              value: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
            },
            { name: 'Auto-Stake', value: 'false' },
          ],
        },
        joinNetworkResult.Memory,
      );

      // check the gateway record from contract
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
        },
        updateGatewaySettingsResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);

      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 50_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: joinNetworkData.startTimestamp,
        settings: {
          label: 'new-label',
          note: 'new-note',
          fqdn: 'new-fqdn',
          port: 80,
          protocol: 'https',
          autoStake: false,
          allowDelegatedStaking: false,
          minDelegatedStake: 1_000_000_000,
          delegateRewardShareRatio: 10,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
      });
    });

    it('should allow updating the gateway settings and services', async () => {
      const validGatewayTagsWithServices = [
        ...validGatewayTags,
        {
          name: 'Services',
          value: JSON.stringify({
            bundlers: [
              {
                fqdn: 'bundler1.example.com',
                port: 443,
                protocol: 'https',
                path: '/bundler1',
              },
              {
                fqdn: 'bundler2.example.com',
                port: 443,
                protocol: 'https',
                path: '/',
              },
            ],
          }),
        },
      ];
      const joinNetworkResult = await handle({
        Tags: validGatewayTagsWithServices,
      });

      const joinNetworkData = JSON.parse(joinNetworkResult.Messages[0].Data);

      const updateGatewaySettingsResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Update-Gateway-Settings' },
            { name: 'Label', value: 'new-label' },
            { name: 'Note', value: 'new-note' },
            { name: 'FQDN', value: 'new-fqdn' },
            { name: 'Port', value: '80' },
            { name: 'Protocol', value: 'https' },
            { name: 'Allow-Delegated-Staking', value: 'false' },
            { name: 'Min-Delegated-Stake', value: '1000000000' }, // 1K IO
            { name: 'Delegate-Reward-Share-Ratio', value: '10' },
            {
              name: 'Properties',
              value: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
            },
            { name: 'Auto-Stake', value: 'false' },
            {
              name: 'Services',
              value: JSON.stringify({
                bundlers: [
                  {
                    fqdn: 'updated-bundler.example.com',
                    port: 443,
                    protocol: 'https',
                    path: '/newpath',
                  },
                ],
              }),
            },
          ],
        },
        joinNetworkResult.Memory,
      );

      // check the gateway record from contract
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
        },
        updateGatewaySettingsResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);

      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 50_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: joinNetworkData.startTimestamp,
        settings: {
          label: 'new-label',
          note: 'new-note',
          fqdn: 'new-fqdn',
          port: 80,
          protocol: 'https',
          autoStake: false,
          allowDelegatedStaking: false,
          minDelegatedStake: 1_000_000_000,
          delegateRewardShareRatio: 10,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
        },
        services: {
          bundlers: [
            {
              fqdn: 'updated-bundler.example.com',
              port: 443,
              protocol: 'https',
              path: '/newpath',
            },
          ],
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
      });
    });
  });

  describe('Increase-Operator-Stake', () => {
    // join the network and then increase stake
    it('should allow increasing operator stake', async () => {
      const joinNetworkResult = await handle({
        Tags: validGatewayTags,
      });

      const joinNetworkData = JSON.parse(joinNetworkResult.Messages[0].Data);

      const increaseStakeResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Increase-Operator-Stake' },
            { name: 'Quantity', value: '10000000000' }, // 10K IO
          ],
        },
        joinNetworkResult.Memory,
      );

      // check the gateway record from contract
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
        },
        increaseStakeResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 60_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: joinNetworkData.startTimestamp,
        settings: {
          label: 'test-gateway',
          note: 'test-note',
          fqdn: 'test-fqdn',
          port: 443,
          protocol: 'https',
          allowDelegatedStaking: true,
          minDelegatedStake: 500_000_000,
          delegateRewardShareRatio: 0,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          autoStake: true,
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
      });
    });
  });

  describe('Decrease-Operator-Stake', () => {
    // join the network and then increase stake
    it('should allow decreasing the operator stake', async () => {
      // filter the operator-stake tag
      const overrideTags = validGatewayTags.filter(
        (tag) => tag.name !== 'Operator-Stake',
      );

      const joinNetworkResult = await handle({
        Tags: [
          ...overrideTags,
          { name: 'Operator-Stake', value: '60000000000' }, // 60K IO
        ],
      });

      const joinNetworkData = JSON.parse(joinNetworkResult.Messages[0].Data);

      const decreaseStakeResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Decrease-Operator-Stake' },
            { name: 'Quantity', value: '10000000000' }, // 10K IO
          ],
        },
        joinNetworkResult.Memory,
      );

      const decreaseResult = JSON.parse(decreaseStakeResult.Messages[0].Data);

      // check the gateway record from contract
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
        },
        decreaseStakeResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 50_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: {
          [STUB_ADDRESS]: {
            balance: 10_000_000_000,
            startTimestamp: decreaseResult.vaults[STUB_ADDRESS].startTimestamp,
            endTimestamp:
              decreaseResult.vaults[STUB_ADDRESS].startTimestamp +
              1000 * 60 * 60 * 24 * 30, // thirty days
          },
        },
        startTimestamp: joinNetworkData.startTimestamp,
        settings: {
          label: 'test-gateway',
          note: 'test-note',
          fqdn: 'test-fqdn',
          port: 443,
          protocol: 'https',
          allowDelegatedStaking: true,
          minDelegatedStake: 500_000_000,
          delegateRewardShareRatio: 0,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          autoStake: true,
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
      });
    });
  });

  // leave network
  describe('Leave-Network', () => {
    it('should allow leaving the network', async () => {
      const joinNetworkResult = await handle({
        Tags: validGatewayTags,
      });

      const joinNetworkData = JSON.parse(joinNetworkResult.Messages[0].Data);

      const leaveNetworkResult = await handle(
        {
          Tags: [{ name: 'Action', value: 'Leave-Network' }],
        },
        joinNetworkResult.Memory,
      );

      const leaveNetworkData = JSON.parse(leaveNetworkResult.Messages[0].Data);

      // check the gateway record from contract
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
        },
        leaveNetworkResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 0,
        totalDelegatedStake: 0,
        status: 'leaving',
        delegates: [],
        endTimestamp:
          leaveNetworkData.startTimestamp + 1000 * 60 * 60 * 24 * 90, // 90 days
        vaults: {
          [STUB_ADDRESS]: {
            balance: 50_000_000_000,
            startTimestamp: leaveNetworkData.startTimestamp,
            endTimestamp:
              leaveNetworkData.startTimestamp + 1000 * 60 * 60 * 24 * 90, // 90 days
          },
        },
        startTimestamp: joinNetworkData.startTimestamp,
        settings: {
          label: 'test-gateway',
          note: 'test-note',
          fqdn: 'test-fqdn',
          port: 443,
          protocol: 'https',
          allowDelegatedStaking: true,
          minDelegatedStake: 500_000_000,
          delegateRewardShareRatio: 0,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          autoStake: true,
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
      });
    });
  });

  describe('Delegate-Stake', () => {
    let sharedMemory;
    let joinedGateway;
    // transfer some tokens to different address
    const newStubAddress = ''.padEnd(43, '2');

    before(async () => {
      const joinNetworkResult = await handle({
        Tags: validGatewayTags,
      });

      joinedGateway = JSON.parse(joinNetworkResult.Messages[0].Data);

      // transfer some tokens to different address
      const transferResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: newStubAddress },
            { name: 'Quantity', value: '2000000000' }, // 2K IO
          ],
        },
        joinNetworkResult.Memory,
      );
      sharedMemory = transferResult.Memory;
    });

    it('should allow delegating stake', async () => {
      const delegateStakeResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Timestamp: stubbedTimestamp,
          Tags: [
            { name: 'Action', value: 'Delegate-Stake' },
            { name: 'Quantity', value: '2000000000' }, // 2K IO
            { name: 'Address', value: STUB_ADDRESS },
          ],
        },
        sharedMemory,
      );

      // check the gateway record from contract
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
        },
        delegateStakeResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.deepEqual(
        {
          [newStubAddress]: {
            delegatedStake: 2_000_000_000,
            startTimestamp: stubbedTimestamp,
            vaults: [],
          },
        },
        gatewayData.delegates,
      );
      assert.deepEqual(gatewayData.totalDelegatedStake, 2_000_000_000);
      sharedMemory = delegateStakeResult.Memory;
    });

    it('should allow withdrawing stake from a gateway', async () => {
      const decreaseStakeTimestamp = stubbedTimestamp + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const decreaseStakeResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Timestamp: decreaseStakeTimestamp,
          Id: ''.padEnd(43, 'x'),
          Tags: [
            { name: 'Action', value: 'Decrease-Delegate-Stake' },
            { name: 'Address', value: STUB_ADDRESS },
            { name: 'Quantity', value: '1000000000' }, // 1K IO
          ],
        },
        sharedMemory,
      );
      // get the gateway record
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
          Timestamp: decreaseStakeTimestamp + 1,
        },
        decreaseStakeResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.deepEqual(gatewayData.delegates, {
        [newStubAddress]: {
          delegatedStake: 1_000_000_000,
          startTimestamp: stubbedTimestamp,
          vaults: {
            [''.padEnd(43, 'x')]: {
              balance: 1_000_000_000,
              startTimestamp: decreaseStakeTimestamp, // 15 minutes after stubbedTimestamp
              endTimestamp: decreaseStakeTimestamp + 1000 * 60 * 60 * 24 * 30, // 30 days
            },
          },
        },
      });
      assert.deepEqual(gatewayData.totalDelegatedStake, 1_000_000_000);
      sharedMemory = decreaseStakeResult.Memory;
    });

    it('should allow canceling a withdrawal', async () => {
      const cancelWithdrawalTimestamp = stubbedTimestamp + 1000 * 60 * 30; // 30 minutes after stubbedTimestamp
      const cancelWithdrawalResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Tags: [
            { name: 'Action', value: 'Cancel-Delegate-Withdrawal' },
            { name: 'Address', value: STUB_ADDRESS },
            { name: 'Vault-Id', value: ''.padEnd(43, 'x') },
          ],
          Timestamp: cancelWithdrawalTimestamp,
        },
        sharedMemory,
      );

      // now get the gateway record
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
          Timestamp: cancelWithdrawalTimestamp + 1,
        },
        cancelWithdrawalResult.Memory,
      );

      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      
      assert.deepEqual(gatewayData.delegates, {
        [newStubAddress]: {
          delegatedStake: 2_000_000_000,
          startTimestamp: stubbedTimestamp,
          vaults: [],
        },
      });
      assert.deepEqual(gatewayData.totalDelegatedStake, 2_000_000_000);
      sharedMemory = cancelWithdrawalResult.Memory;
    });

    it('should not decrease delegate stake with invalid instant withdrawal tag', async () => {
      const instantWithdrawalTimestamp = stubbedTimestamp + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const decreaseStakeResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Timestamp: instantWithdrawalTimestamp,
          Id: ''.padEnd(43, 'x'),
          Tags: [
            { name: 'Action', value: 'Decrease-Delegate-Stake' },
            { name: 'Address', value: STUB_ADDRESS },
            { name: 'Quantity', value: '1000000000' }, // 1K IO
            { name: 'Instant', value: 'false' }, // FOR SOME REASON THIS WORKS IF YOU PUT 'false' :O
          ],
        },
        sharedMemory,
      );
    
      // get the updated gateway record
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
          Timestamp: instantWithdrawalTimestamp + 1,
        },
        decreaseStakeResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.deepEqual(gatewayData.totalDelegatedStake, 2_000_000_000);
    });

    it('should decrease delegate stake with instant withdrawal', async () => {
      const instantWithdrawalTimestamp = stubbedTimestamp + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const decreaseStakeResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Timestamp: instantWithdrawalTimestamp,
          Id: ''.padEnd(43, 'x'),
          Tags: [
            { name: 'Action', value: 'Decrease-Delegate-Stake' },
            { name: 'Address', value: STUB_ADDRESS },
            { name: 'Quantity', value: '1000000000' }, // 1K IO
            { name: 'Instant', value: "true" },
          ],
        },
        sharedMemory,
      );
    
      // get the updated gateway record
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
          Timestamp: instantWithdrawalTimestamp + 1,
        },
        decreaseStakeResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      // Assertions
      assert.deepEqual(gatewayData.delegates, {
        [newStubAddress]: {
          delegatedStake: 1_000_000_000,
          startTimestamp: stubbedTimestamp,
          vaults: [],
        },
      });
      assert.deepEqual(gatewayData.totalDelegatedStake, 1_000_000_000);
      sharedMemory = decreaseStakeResult.Memory;

    });

    it('should allow decrease delegate stake from a gateway followed up with instant withdrawal', async () => {
      const decreaseStakeTimestamp = stubbedTimestamp + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const decreaseStakeResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Timestamp: decreaseStakeTimestamp,
          Id: ''.padEnd(43, 'x'),
          Tags: [
            { name: 'Action', value: 'Decrease-Delegate-Stake' },
            { name: 'Address', value: STUB_ADDRESS },
            { name: 'Quantity', value: '1000000000' }, // 1K IO
          ],
        },
        sharedMemory,
      );

      // get the updated gateway record
      let gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
          Timestamp: decreaseStakeTimestamp + 1,
        },
        decreaseStakeResult.Memory,
      );
      let gatewayData = JSON.parse(gateway.Messages[0].Data);  

      const instantDecreaseStakeTimestamp = decreaseStakeTimestamp + 1000 * 60 * 60; // 60 minutes after stubbedTimestamp
      const instantDecreaseStakeResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Timestamp: instantDecreaseStakeTimestamp,
          Id: ''.padEnd(43, 'x'),
          Tags: [
            { name: 'Action', value: 'Instant-Delegate-Withdrawal' }, // TO DO - MAKE THIS HANDLER!
            { name: 'Address', value: STUB_ADDRESS },
            { name: 'Vault-Id', value: ''.padEnd(43, 'x') },
          ],
        },
        decreaseStakeResult.Memory,
      );

      // get the gateway record
      gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
          Timestamp: instantDecreaseStakeTimestamp + 1,
        },
        instantDecreaseStakeResult.Memory,
      );

      gatewayData = JSON.parse(gateway.Messages[0].Data);
      console.log ("1: ", gatewayData)
      assert.deepEqual(gatewayData.delegates, []);
      assert.deepEqual(gatewayData.totalDelegatedStake, 0);
      sharedMemory = instantDecreaseStakeResult.Memory;
    });


  });
});
