import { createAosLoader } from './utils.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  validGatewayTags,
} from '../tools/constants.mjs';

describe('Tick', async () => {
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

  it('should prune record that are expired and after the grace period', async () => {
    let mem = startMemory;
    const buyRecordResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Buy-Record' },
          { name: 'Name', value: 'test-name' },
          { name: 'Purchase-Type', value: 'lease' },
          { name: 'Years', value: '1' },
          { name: 'Process-Id', value: ''.padEnd(43, 'a') },
        ],
      },
      mem,
    );

    const realRecord = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      buyRecordResult.Memory,
    );

    const buyRecordData = JSON.parse(realRecord.Messages[0].Data);
    assert.deepEqual(buyRecordData, {
      processId: ''.padEnd(43, 'a'),
      purchasePrice: 600000000,
      type: 'lease',
      undernameLimit: 10,
      startTimestamp: buyRecordData.startTimestamp,
      endTimestamp: buyRecordData.endTimestamp,
    });

    // mock the passage of time and tick with a future timestamp
    const futureTimestamp =
      Date.now() + buyRecordData.endTimestamp + 1000 * 60 * 60 * 24 * 14;
    const futureTick = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: (futureTimestamp + 1).toString() },
        ],
      },
      buyRecordResult.Memory,
    );

    // the record should be pruned
    const prunedRecord = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      futureTick.Memory,
    );

    const prunedRecordData = JSON.parse(prunedRecord.Messages[0].Data);

    assert.deepEqual(undefined, prunedRecordData);
  });

  it('should prune gateways that are expired', async () => {
    const joinNetworkResult = await handle({
      Tags: validGatewayTags,
    });
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
    assert.deepEqual(gatewayData.status, 'joined');

    // leave the network
    const leaveNetworkResult = await handle(
      {
        Tags: [{ name: 'Action', value: 'Leave-Network' }],
      },
      joinNetworkResult.Memory,
    );

    // check the gateways status is leaving
    const leavingGateway = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Gateway' },
          { name: 'Address', value: STUB_ADDRESS },
        ],
      },
      leaveNetworkResult.Memory,
    );

    const leavingGatewayData = JSON.parse(leavingGateway.Messages[0].Data);
    assert.deepEqual(leavingGatewayData.status, 'leaving');
    // TODO: check delegates and operator stake are vaulted

    // expedite the timestamp to the future
    const futureTimestamp = leavingGatewayData.endTimestamp + 1;
    const futureTick = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: futureTimestamp.toString() },
        ],
      },
      leaveNetworkResult.Memory,
    );

    // check the gateway is pruned
    const prunedGateway = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Gateway' },
          { name: 'Address', value: STUB_ADDRESS },
        ],
      },
      futureTick.Memory,
    );

    const prunedGatewayData = JSON.parse(prunedGateway.Messages[0].Data);
    assert.deepEqual(undefined, prunedGatewayData);
  });

  // vaulting is not working as expected, need to fix before enabling this test
  it.skip('should prune and return vaults that are expired', async () => {
    const startTimestamp = Date.now();
    const lockLengthMs = 1209600000;
    const createVaultResult = await handle({
      Tags: [
        {
          name: 'Action',
          value: 'Create-Vault',
        },
        {
          name: 'Quantity',
          value: '1000000000',
        },
        {
          name: 'Lock-Length',
          value: lockLengthMs.toString(), // the minimum lock length is 14 days
        },
        {
          name: 'Timestamp',
          value: startTimestamp.toString(),
        },
      ],
    });
    // parse the data and ensure the vault was created
    const createdVaultData = JSON.parse(createVaultResult.Messages[0].Data);
    assert.deepEqual(createdVaultData.balance, '1000000000');
    assert.deepEqual(createdVaultData.startTimestamp, startTimestamp);
    assert.deepEqual(
      createdVaultData.endTimestamp,
      startTimestamp + lockLengthMs,
    );

    const vaultId = createVaultResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Vault-Id',
    ).value;
    // assert the vault id is in the tags
    assert.deepEqual(vaultId, DEFAULT_HANDLE_OPTIONS.Id);

    // check that vault exists
    const vault = await handle(
      {
        Tags: [
          {
            name: 'Action',
            value: 'Vaults',
          },
          {
            name: 'Vault-Id',
            value: vaultId,
          },
        ],
      },
      createVaultResult.Memory,
    );
    const vaultData = JSON.parse(vault.Messages[0].Data);
    assert.deepEqual(vaultData.balance, '1000000000');
    assert.deepEqual(createdVaultData.startTimestamp, startTimestamp);
    assert.deepEqual(
      createdVaultData.endTimestamp,
      startTimestamp + lockLengthMs,
    );
    // mock the passage of time and tick with a future timestamp
    const futureTimestamp = vaultData.endTimestamp + 1;
    const futureTick = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: futureTimestamp.toString() },
        ],
      },
      createVaultResult.Memory,
    );

    // check the vault is pruned
    const prunedVault = await handle(
      {
        Tags: [{ name: 'Action', value: 'Vault' }],
      },
      futureTick.Memory,
    );

    const prunedVaultData = JSON.parse(prunedVault.Messages[0].Data);
    assert.deepEqual(undefined, prunedVaultData);
  });
});
