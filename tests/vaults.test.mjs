import { createAosLoader } from './utils.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  DEFAULT_HANDLE_OPTIONS,
  AO_LOADER_HANDLER_ENV,
} from '../tools/constants.mjs';

describe('Vaults', async () => {
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

  it('should create a vault', async () => {
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
  });
});
