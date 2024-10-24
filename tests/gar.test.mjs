import { createAosLoader } from './utils.mjs';
import { describe, it, before, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_TIMESTAMP,
  STUB_MESSAGE_ID,
  STUB_ADDRESS,
  PROCESS_OWNER,
  validGatewayTags,
} from '../tools/constants.mjs';

const stubbedTimestamp = STUB_TIMESTAMP + 1000 * 60 * 60 * 24 * 30; // 30 days after stubbedTimestamp
describe('GatewayRegistry', async () => {
  const { handle: originalHandle, memory: startMemory } =
    await createAosLoader();
  let sharedMemory = startMemory; // memory we'll use across unique tests;
  async function handle(options = {}, mem = sharedMemory) {
    return originalHandle(
      mem,
      {
        ...DEFAULT_HANDLE_OPTIONS,
        ...options,
      },
      AO_LOADER_HANDLER_ENV,
    );
  }

  const transfer = async ({
    recipient = STUB_ADDRESS,
    quantity = 100_000_000_000,
    memory = sharedMemory,
  } = {}) => {
    const transferResult = await handle(
      {
        From: PROCESS_OWNER,
        Owner: PROCESS_OWNER,
        Tags: [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: recipient },
          { name: 'Quantity', value: quantity },
          { name: 'Cast', value: false },
        ],
      },
      memory,
    );

    // assert no error tag
    const errorTag = transferResult.Messages?.[0]?.Tags?.find(
      (tag) => tag.Name === 'Error',
    );
    assert.strictEqual(errorTag, undefined);

    return transferResult.Memory;
  };

  beforeEach(async () => {
    sharedMemory = await transfer({ sharedMemory });
    const joinNetworkResult = await handle(
      {
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
        Tags: validGatewayTags,
      },
      sharedMemory,
    );
    sharedMemory = joinNetworkResult.Memory;
  });

  describe('Join-Network', () => {
    it('should allow joining of the network record', async () => {
      // check the gateway record from contract
      const gateway = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Gateway' },
            { name: 'Address', value: STUB_ADDRESS },
          ],
        },
        sharedMemory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 100_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: STUB_TIMESTAMP,
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

  describe('Update-Gateway-Settings', () => {
    it('should allow updating the gateway settings', async () => {
      const updateGatewaySettingsResult = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
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
        updateGatewaySettingsResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);

      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 100_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: STUB_TIMESTAMP,
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
  });

  describe('Increase-Operator-Stake', () => {
    // join the network and then increase stake
    it('should allow increasing operator stake', async () => {
      const increaseStakeResult = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Increase-Operator-Stake' },
            { name: 'Quantity', value: '10000000000' }, // 10K IO
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
        increaseStakeResult.Memory,
      );
      const gatewayData = JSON.parse(gateway.Messages[0].Data);
      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 110_000_000_000,
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: STUB_TIMESTAMP,
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
    it('should allow decreasing the operator stake as long as it is above the minimum', async () => {
      const decreaseStakeResult = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [
            { name: 'Action', value: 'Decrease-Operator-Stake' },
            { name: 'Quantity', value: '50000000000' }, // 50K IO
          ],
        },
        sharedMemory,
      );

      // assert no error tag
      const errorTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.Name === 'Error',
      );
      assert.strictEqual(errorTag, undefined);

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
          [STUB_MESSAGE_ID]: {
            balance: 50_000_000_000,
            startTimestamp: STUB_TIMESTAMP,
            endTimestamp: STUB_TIMESTAMP + 1000 * 60 * 60 * 24 * 30, // thirty days
          },
        },
        startTimestamp: STUB_TIMESTAMP,
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
      const leaveNetworkResult = await handle(
        {
          From: STUB_ADDRESS,
          Owner: STUB_ADDRESS,
          Tags: [{ name: 'Action', value: 'Leave-Network' }],
        },
        sharedMemory,
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
          [STUB_MESSAGE_ID]: {
            balance: 50_000_000_000,
            startTimestamp: leaveNetworkData.startTimestamp,
            endTimestamp:
              leaveNetworkData.startTimestamp + 1000 * 60 * 60 * 24 * 30, // 30 days
          },
        },
        startTimestamp: STUB_TIMESTAMP,
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
    // transfer some tokens to different address
    const newStubAddress = ''.padEnd(43, '3');

    it('should allow delegating stake', async () => {
      // TRANSFER 2K IO to our next stubbed address
      const quantity = 2_000_000_000;
      const transferMemory = await transfer({
        recipient: newStubAddress,
        quantity: quantity,
        memory: sharedMemory,
      });

      const delegateStakeResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Tags: [
            { name: 'Action', value: 'Delegate-Stake' },
            { name: 'Quantity', value: quantity }, // 2K IO
            { name: 'Address', value: STUB_ADDRESS }, // our gateway address
          ],
          Timestamp: STUB_TIMESTAMP + 1,
        },
        transferMemory,
      );

      // assert no error tag
      const errorTag = delegateStakeResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.Name === 'Error',
      );
      assert.strictEqual(errorTag, undefined);

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

      assert.deepEqual(gatewayData.delegates, {
        [newStubAddress]: {
          delegatedStake: quantity,
          startTimestamp: STUB_TIMESTAMP + 1,
          vaults: [],
        },
      });
      assert.deepEqual(gatewayData.totalDelegatedStake, quantity);
      sharedMemory = delegateStakeResult.Memory;
    });

    it('should allow withdrawing stake from a gateway', async () => {
      const decreaseStakeTimestamp = STUB_TIMESTAMP + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
      const decreaseStakeResult = await handle(
        {
          From: newStubAddress,
          Owner: newStubAddress,
          Timestamp: decreaseStakeTimestamp,
          Id: ''.padEnd(43, 'x'),
          Tags: [
            { name: 'Action', value: 'Decrease-Delegate-Stake' },
            { name: 'Address', value: STUB_ADDRESS },
            { name: 'Quantity', value: '500000000' }, // 500 IO
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
          delegatedStake: 1_500_000_000,
          startTimestamp: STUB_TIMESTAMP + 1,
          vaults: {
            [''.padEnd(43, 'x')]: {
              balance: 500_000_000,
              startTimestamp: decreaseStakeTimestamp, // 15 minutes after stubbedTimestamp
              endTimestamp: decreaseStakeTimestamp + 1000 * 60 * 60 * 24 * 30, // 30 days
            },
          },
        },
      });
      assert.deepEqual(gatewayData.totalDelegatedStake, 1_500_000_000);
      sharedMemory = decreaseStakeResult.Memory;
    });

    it('should allow canceling a withdrawal', async () => {
      const cancelWithdrawalTimestamp = STUB_TIMESTAMP + 1000 * 60 * 30; // 30 minutes after stubbedTimestamp
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
          startTimestamp: STUB_TIMESTAMP + 1,
          vaults: [],
        },
      });
      assert.deepEqual(gatewayData.totalDelegatedStake, 2_000_000_000);
      sharedMemory = cancelWithdrawalResult.Memory;
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
            { name: 'Instant', value: 'true' },
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
          startTimestamp: STUB_TIMESTAMP + 1,
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
      assert.deepEqual(gatewayData.delegates, []);
      assert.deepEqual(gatewayData.totalDelegatedStake, 0);
      sharedMemory = instantDecreaseStakeResult.Memory;
    });
  });
});
