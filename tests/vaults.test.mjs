import { createAosLoader, assertNoResultError } from './utils.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  DEFAULT_HANDLE_OPTIONS,
  AO_LOADER_HANDLER_ENV,
  PROCESS_OWNER,
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

  const createVault = async ({
    memory,
    quantity,
    lockLengthMs,
    from = PROCESS_OWNER,
    messageId,
  }) => {
    const createVaultResult = await handle(
      {
        Id: messageId,
        From: from,
        Owner: from,
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
            value: lockLengthMs.toString(),
          },
        ],
      },
      memory,
    );

    assertNoResultError(createVaultResult);
    return { result: createVaultResult, memory: createVaultResult.Memory };
  };

  describe('createVault', () => {
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

  describe('extendVault', () => {
    it('should extend a vault', async () => {
      const lockLengthMs = 1209600000;
      const quantity = 1000000000;

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
            value: lockLengthMs.toString(),
          },
        ],
      });

      // ensure no error
      const errorTag = createVaultResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.deepEqual(errorTag, undefined);

      const createVaultResultData = JSON.parse(
        createVaultResult.Messages[0].Data,
      );
      const vaultId = createVaultResult.Messages[0].Tags.find(
        (tag) => tag.name === 'Vault-Id',
      ).value;

      const extendVaultResult = await handle(
        {
          Tags: [
            {
              name: 'Action',
              value: 'Extend-Vault',
            },
            {
              name: 'Vault-Id',
              value: vaultId,
            },
            {
              name: 'Extend-Length',
              value: lockLengthMs.toString(),
            },
          ],
        },
        createVaultResult.Memory,
      );

      // ensure no error
      const extendVaultErrorTag = extendVaultResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.deepEqual(extendVaultErrorTag, undefined);

      const extendVaultResultData = JSON.parse(
        extendVaultResult.Messages[0].Data,
      );
      assert.deepEqual(
        extendVaultResultData.balance,
        createVaultResultData.balance,
        quantity,
      );
    });
  });

  describe('increaseVaultBalance', () => {
    it('should increase a vault balance', async () => {
      const quantity = 1000000000;
      const lockLengthMs = 1209600000;
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
            value: lockLengthMs.toString(),
          },
        ],
      });

      // ensure no error
      const errorTag = createVaultResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.deepEqual(errorTag, undefined);

      const createVaultResultData = JSON.parse(
        createVaultResult.Messages[0].Data,
      );

      const vaultId = createVaultResult.Messages[0].Tags.find(
        (tag) => tag.name === 'Vault-Id',
      ).value;

      const increaseVaultBalanceResult = await handle(
        {
          Tags: [
            {
              name: 'Action',
              value: 'Increase-Vault',
            },
            {
              name: 'Vault-Id',
              value: vaultId,
            },
            {
              name: 'Quantity',
              value: quantity.toString(),
            },
          ],
        },
        createVaultResult.Memory,
      );

      // ensure no error
      const increaseVaultBalanceErrorTag =
        increaseVaultBalanceResult.Messages?.[0]?.Tags?.find(
          (tag) => tag.name === 'Error',
        );
      assert.deepEqual(increaseVaultBalanceErrorTag, undefined);

      const increaseVaultBalanceResultData = JSON.parse(
        increaseVaultBalanceResult.Messages[0].Data,
      );
      assert.deepEqual(
        increaseVaultBalanceResultData.balance,
        createVaultResultData.balance + quantity,
      );
    });
  });

  describe('vaultedTransfer', () => {
    it('should create a vault for the recipient', async () => {
      const quantity = 1000000000;
      const lockLengthMs = 1209600000;
      const recipient = '0x0000000000000000000000000000000000000000';
      const createVaultedTransferResult = await handle({
        Tags: [
          {
            name: 'Action',
            value: 'Vaulted-Transfer',
          },
          {
            name: 'Quantity',
            value: quantity.toString(),
          },
          {
            name: 'Lock-Length',
            value: lockLengthMs.toString(),
          },
          {
            name: 'Recipient',
            value: recipient,
          },
        ],
      });

      // ensure no error
      const errorTag = createVaultedTransferResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.deepEqual(errorTag, undefined);

      // it should create two messages, one for sender and other for recipient
      assert.deepEqual(createVaultedTransferResult.Messages.length, 2);

      const senderMessage = createVaultedTransferResult.Messages.find((msg) =>
        msg.Tags.find(
          (tag) => tag.name === 'Action' && tag.value === 'Debit-Notice',
        ),
      );

      // ensure it is not undefined
      assert.ok(senderMessage);

      const recipientMessage = createVaultedTransferResult.Messages.find(
        (msg) =>
          msg.Tags.find(
            (tag) =>
              tag.name === 'Action' && tag.value === 'Create-Vault-Notice',
          ),
      );

      assert.ok(recipientMessage);

      const vaultId = recipientMessage.Tags.find(
        (tag) => tag.name === 'Vault-Id',
      ).value;

      // ensure vault id is defined
      assert.ok(vaultId);

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
            {
              name: 'Address',
              value: recipient,
            },
          ],
        },
        createVaultedTransferResult.Memory,
      );

      const createdVaultData = JSON.parse(
        createVaultedTransferResult.Messages[0].Data,
      );

      const vaultData = JSON.parse(vault.Messages[0].Data);
      assert.deepEqual(vaultData.balance, quantity);
      assert.deepEqual(
        vaultData.startTimestamp,
        createdVaultData.startTimestamp,
      );
      assert.deepEqual(
        vaultData.endTimestamp,
        createdVaultData.startTimestamp + lockLengthMs,
      );
    });
  });

  describe('getPaginatedVaults', () => {
    it('should get paginated vaults', async () => {
      const vaultId1 = 'unique-id-1-'.padEnd(43, 'a');
      const { memory: updatedMemory } = await createVault({
        quantity: 500,
        lockLengthMs: 1209600000,
        memory: startMemory,
        messageId: vaultId1,
      });

      const secondVaulter = 'unique-second-address-'.padEnd(43, 'a');
      const transferResult = await handle(
        {
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: secondVaulter },
            { name: 'Quantity', value: 600 }, // 100 IO
            { name: 'Cast', value: false },
          ],
        },
        updatedMemory,
      );

      const vaultId2 = 'unique-id-2-'.padEnd(43, 'a');
      const { memory: updatedMemory2 } = await createVault({
        quantity: 600,
        lockLengthMs: 1209600000,
        memory: transferResult.Memory,
        from: secondVaulter,
        messageId: vaultId2,
      });

      let cursor = '';
      let fetchedVaults = [];
      while (true) {
        const paginatedVaults = await handle(
          {
            Tags: [
              { name: 'Action', value: 'Paginated-Vaults' },
              { name: 'Cursor', value: cursor },
              { name: 'Limit', value: '1' },
            ],
          },
          updatedMemory2,
        );

        // parse items, nextCursor
        const { items, nextCursor, hasMore, sortBy, sortOrder, totalItems } =
          JSON.parse(paginatedVaults.Messages?.[0]?.Data);

        assert.equal(totalItems, 2);
        assert.equal(items.length, 1);
        assert.equal(sortBy, 'balance');
        assert.equal(sortOrder, 'desc');
        assert.equal(hasMore, !!nextCursor);
        cursor = nextCursor;
        fetchedVaults.push(...items);
        if (!cursor) break;
      }

      assert.deepEqual(fetchedVaults, [
        {
          address: secondVaulter,
          vault: {
            [vaultId2]: {
              balance: 600,
              startTimestamp: 21600000,
              endTimestamp: 1231200000,
            },
          },
        },
        {
          address: PROCESS_OWNER,
          vault: {
            [vaultId1]: {
              balance: 500,
              startTimestamp: 21600000,
              endTimestamp: 1231200000,
            },
          },
        },
      ]);
    });
  });
});
