const { createAntAosLoader } = require('./utils');
const { describe, it } = require('node:test');
const assert = require('node:assert');
const {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
} = require('../tools/constants');

describe('GatewayRegistry', async () => {
  const { handle: originalHandle, memory: startMemory } =
    await createAntAosLoader();

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

  describe('Join-Network', () => {
    const validGatewayTags = [
      { name: 'Action', value: 'Join-Network' },
      { name: 'Label', value: 'test-gateway' },
      { name: 'Note', value: 'test-note' },
      { name: 'FQDN', value: 'test-fqdn' },
      { name: 'Operator-Stake', value: '500000000000' }, // 50K IO
      { name: 'Port', value: '443' },
      { name: 'Protocol', value: 'https' },
      { name: 'Allow-Delegated-Staking', value: 'true' },
      { name: 'Min-Delegated-Stake', value: '500000000' }, // 500 IO
      { name: 'Delegate-Reward-Share-Ratio', value: '0' },
      { name: 'Observer-Address', value: STUB_ADDRESS },
      {
        name: 'Properties',
        value: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
      },
      { name: 'Auto-Stake', value: 'true' },
    ];

    it('should allow joining of the network record', async () => {
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
        operatorStake: 500_000_000_000,
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
    ];
    // for each bad input tag append it to the good tags and verify it fails
    for (const tags of badInputTags) {
      it(`should fail to join the network with bad input: ${JSON.stringify(tags)}`, async () => {
        const overwriteTags = validGatewayTags.filter((tag) => {
          return !tags.map((t) => t.name).includes(tag.name);
        });
        const joinNetworkResult = await handle({
          Tags: [...overwriteTags, ...tags],
        });

        console.log(joinNetworkResult);

        // confirm there is an error tag
        const errorTag = joinNetworkResult.Messages[0].Tags.find(
          (tag) => tag.name === 'Error',
        );
        //
        assert(errorTag, 'Error tag not found');

        // confirm gateway did not join
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
        // assert it does not exist
        assert.equal(gatewayData, null);
      });
    }
  });
});
