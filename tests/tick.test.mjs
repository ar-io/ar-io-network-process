import { createAosLoader } from './utils.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_ADDRESS,
  validGatewayTags,
  PROCESS_OWNER,
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

    const transfer = async ({
      recipient = STUB_ADDRESS,
      quantity = 100_000_000_000,
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
        // memory
      );

      // assert no error tag
      const errorTag = transferResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.Name === 'Error',
      );
      assert.strictEqual(errorTag, undefined);

    return transferResult.Memory;
  };

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
      buyRecordData.endTimestamp + 1000 * 60 * 60 * 24 * 14 + 1;
    const futureTickResult = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Tick' },
          { name: 'Timestamp', value: (futureTimestamp + 1).toString() },
        ],
      },
      buyRecordResult.Memory,
    );

    const tickEvent = JSON.parse(
      futureTickResult.Output.data
        .split('\n')
        .filter((line) => line.includes('_e'))[0],
    );
    assert.equal(tickEvent['Records-Count'], 0);
    assert.equal(tickEvent['Pruned-Records-Count'], 1);
    assert.deepEqual(tickEvent['Pruned-Records'], ['test-name']);

    // the record should be pruned
    const prunedRecord = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Record' },
          { name: 'Name', value: 'test-name' },
        ],
      },
      futureTickResult.Memory,
    );

    const prunedRecordData = JSON.parse(prunedRecord.Messages[0].Data);

    assert.deepEqual(undefined, prunedRecordData);
  });

  it('should prune gateways that are expired', async () => {
    const memory = await transfer({
      recipient: STUB_ADDRESS,
      quantity: 100_000_000_000,
    });

    const joinNetworkResult = await handle({
      Tags: validGatewayTags,
      From: STUB_ADDRESS,
      Owner: STUB_ADDRESS,
    }, memory);

    // assert no error tag
    const errorTag = joinNetworkResult.Messages?.[0]?.Tags?.find(
      (tag) => tag.name === 'Error',
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
      joinNetworkResult.Memory,
    );
    const gatewayData = JSON.parse(gateway.Messages[0].Data);
    assert.deepEqual(gatewayData.status, 'joined');

    // leave the network
    const leaveNetworkResult = await handle(
      {
        From: STUB_ADDRESS,
        Owner: STUB_ADDRESS,
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
  it('should prune vaults that are expired', async () => {
    const lockLengthMs = 1209600000;
    const quantity = 1000000000;
    const balanceBefore = await handle({
      Tags: [{ name: 'Action', value: 'Balance' }],
    });
    const balanceBeforeData = JSON.parse(balanceBefore.Messages[0].Data);
    const createVaultResult = await handle({
      Tags: [
        {
          name: 'Action',
          value: 'Create-Vault',
        },
        {
          name: 'Quantity',
          value: quantity.toString(),
        },
        {
          name: 'Lock-Length',
          value: lockLengthMs.toString(), // the minimum lock length is 14 days
        },
      ],
    });
    // parse the data and ensure the vault was created
    const createVaultResultData = JSON.parse(
      createVaultResult.Messages[0].Data,
    );
    const vaultId = createVaultResult.Messages[0].Tags.find(
      (tag) => tag.name === 'Vault-Id',
    ).value;
    // assert the vault id is in the tags
    assert.deepEqual(vaultId, DEFAULT_HANDLE_OPTIONS.Id);

    // assert the balance is deducted
    const balanceAfterVault = await handle(
      {
        Tags: [{ name: 'Action', value: 'Balance' }],
      },
      createVaultResult.Memory,
    );
    const balanceAfterVaultData = JSON.parse(
      balanceAfterVault.Messages[0].Data,
    );
    assert.deepEqual(balanceAfterVaultData, balanceBeforeData - quantity);

    // check that vault exists
    const vault = await handle(
      {
        Tags: [
          {
            name: 'Action',
            value: 'Vault',
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
    assert.deepEqual(
      createVaultResultData.balance,
      vaultData.balance,
      quantity,
    );
    assert.deepEqual(
      vaultData.startTimestamp,
      createVaultResultData.startTimestamp,
    );
    assert.deepEqual(
      vaultData.endTimestamp,
      createVaultResultData.endTimestamp,
      createVaultResult.startTimestamp + lockLengthMs,
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
    assert.deepEqual(undefined, prunedVault.Messages[0].Data);
    assert.equal(
      prunedVault.Messages[0].Tags.find((tag) => tag.name === 'Error').value,
      'Vault-Not-Found',
    );

    // Check that the balance is returned to the owner
    const ownerBalance = await handle(
      {
        Tags: [
          { name: 'Action', value: 'Balance' },
          { name: 'Target', value: DEFAULT_HANDLE_OPTIONS.Owner },
        ],
      },
      futureTick.Memory,
    );
    const balanceData = JSON.parse(ownerBalance.Messages[0].Data);
    assert.equal(balanceData, balanceBeforeData);
  });
});
