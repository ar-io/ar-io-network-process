import { assertNoResultError } from './utils.mjs';
import { describe, it, before, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import {
  DEFAULT_HANDLE_OPTIONS,
  PROCESS_OWNER,
  STUB_TIMESTAMP,
} from '../tools/constants.mjs';
import {
  getVaults,
  handle,
  startMemory,
  createVault,
  createVaultedTransfer,
  totalTokenSupply,
  getBalance,
} from './helpers.mjs';
import { assertNoInvariants } from './invariants.mjs';

describe('Vaults', async () => {
  let sharedMemory = startMemory;
  let endingMemory;
  beforeEach(async () => {
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    sharedMemory = totalTokenSupplyMemory;
  });

  afterEach(async () => {
    await assertNoInvariants({
      timestamp: STUB_TIMESTAMP,
      memory: endingMemory,
    });
  });

  const assertVaultExists = async ({ vaultId, address, memory }) => {
    const vault = await handle({
      options: {
        Tags: [
          { name: 'Action', value: 'Vault' },
          { name: 'Vault-Id', value: vaultId },
          { name: 'Address', value: address },
        ],
      },
      memory,
      shouldAssertNoResultError: false,
    });
    assertNoResultError(vault);
    // make sure it is a vault
    assert.strictEqual(
      vault.Messages[0].Tags.find((tag) => tag.name === 'Vault-Id').value,
      vaultId,
    );
    return JSON.parse(vault.Messages[0].Data);
  };

  describe('createVault', () => {
    it('should create a vault', async () => {
      const lockLengthMs = 1209600000;
      const quantity = 1000000000;
      const balanceBefore = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Balance' }],
        },
        memory: sharedMemory,
      });
      const balanceBeforeData = JSON.parse(balanceBefore.Messages[0].Data);
      const { result: createVaultResult } = await createVault({
        quantity,
        lockLengthMs,
        from: PROCESS_OWNER,
        memory: sharedMemory,
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
      const balanceAfterVault = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Balance' }],
        },
        memory: createVaultResult.Memory,
      });
      const balanceAfterVaultData = JSON.parse(
        balanceAfterVault.Messages[0].Data,
      );
      assert.deepEqual(balanceAfterVaultData, balanceBeforeData - quantity);

      const vaultData = await assertVaultExists({
        vaultId,
        address: PROCESS_OWNER,
        memory: createVaultResult.Memory,
      });
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
      endingMemory = createVaultResult.Memory;
    });

    it('should throw an error if vault size is too small', async () => {
      const lockLengthMs = 1209600000;
      const quantity = 99999999;
      const balanceBefore = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Balance' }],
        },
        memory: sharedMemory,
      });
      const balanceBeforeData = JSON.parse(balanceBefore.Messages[0].Data);
      const { result: createVaultResult } = await createVault({
        quantity,
        lockLengthMs,
        shouldAssertNoResultError: false,
        memory: sharedMemory,
      });

      const actionTag = createVaultResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Action',
      );
      assert.strictEqual(actionTag.value, 'Invalid-Create-Vault-Notice');
      const errorTag = createVaultResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert(
        errorTag.value.includes(
          'Invalid quantity. Must be integer greater than or equal to 100000000 mARIO',
        ),
      );

      // assert the balance is deducted
      const balanceAfterVault = await handle({
        options: {
          Tags: [{ name: 'Action', value: 'Balance' }],
        },
        memory: createVaultResult.Memory,
      });
      const balanceAfterVaultData = JSON.parse(
        balanceAfterVault.Messages[0].Data,
      );
      assert.deepEqual(balanceAfterVaultData, balanceBeforeData);
      endingMemory = balanceAfterVault.Memory;
    });
  });

  describe('extendVault', () => {
    it('should extend a vault', async () => {
      const lockLengthMs = 1209600000;
      const quantity = 1000000000;

      const { result: createVaultResult } = await createVault({
        quantity,
        lockLengthMs,
        memory: sharedMemory,
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

      const extendVaultResult = await handle({
        options: {
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
        memory: createVaultResult.Memory,
      });

      // ensure no error
      assertNoResultError(extendVaultResult);

      const extendVaultResultData = JSON.parse(
        extendVaultResult.Messages[0].Data,
      );
      assert.deepEqual(
        extendVaultResultData.balance,
        createVaultResultData.balance,
        quantity,
      );
      endingMemory = extendVaultResult.Memory;
    });
  });

  describe('increaseVaultBalance', () => {
    it('should increase a vault balance', async () => {
      const quantity = 1000000000;
      const lockLengthMs = 1209600000;
      const { result: createVaultResult } = await createVault({
        quantity,
        lockLengthMs,
        memory: sharedMemory,
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

      const increaseVaultBalanceResult = await handle({
        options: {
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
        memory: createVaultResult.Memory,
      });

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
      endingMemory = increaseVaultBalanceResult.Memory;
    });
  });

  describe('vaultedTransfer', () => {
    const quantity = 1000000000;
    const lockLengthMs = 1209600000;
    const recipient = '0x0000000000000000000000000000000000000000';

    it('should create a vault for the recipient with a valid address', async () => {
      const { result: createVaultedTransferResult } =
        await createVaultedTransfer({
          quantity,
          lockLengthMs,
          recipient,
          memory: sharedMemory,
        });

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

      const createdVaultData = await assertVaultExists({
        vaultId,
        address: recipient,
        memory: createVaultedTransferResult.Memory,
      });

      assert.deepEqual(createdVaultData.balance, quantity);
      assert.deepEqual(createdVaultData.startTimestamp, STUB_TIMESTAMP);
      assert.deepEqual(
        createdVaultData.endTimestamp,
        STUB_TIMESTAMP + lockLengthMs,
      );
      endingMemory = createVaultedTransferResult.Memory;
    });

    it('should create a revokable vault for the recipient and the controller should be able to revoke that vault', async () => {
      const controller = 'valid-controller-'.padEnd(43, 'a');
      const { result: createVaultedTransferResult } =
        await createVaultedTransfer({
          quantity,
          lockLengthMs,
          recipient,
          from: controller,
          memory: sharedMemory,
          revokable: true,
        });

      const vaultId = createVaultedTransferResult.Messages[0].Tags.find(
        (tag) => tag.name === 'Vault-Id',
      ).value;

      // ensure vault id is defined
      assert.ok(vaultId);

      const expectedVaultData = {
        balance: quantity,
        controller,
        startTimestamp: STUB_TIMESTAMP,
        endTimestamp: STUB_TIMESTAMP + lockLengthMs,
      };

      const createdVaultData = await assertVaultExists({
        vaultId,
        address: recipient,
        memory: createVaultedTransferResult.Memory,
      });
      assert.deepEqual(createdVaultData, expectedVaultData);

      // Assert balance is gone for controller
      const controllerBalance = await getBalance({
        address: controller,
        memory: createVaultedTransferResult.Memory,
      });
      assert.deepEqual(controllerBalance, 0);

      // Revoke the vault
      const result = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Revoke-Vault' },
            { name: 'Recipient', value: recipient },
            { name: 'Vault-Id', value: vaultId },
          ],
          From: controller,
          Owner: controller,
        },
        memory: createVaultedTransferResult.Memory,
      });

      assert.deepEqual(result.Messages.length, 2);
      const recipientMessageAfterRevoke = result.Messages.find((msg) =>
        msg.Tags.find(
          (tag) => tag.name === 'Action' && tag.value === 'Revoke-Vault-Notice',
        ),
      );
      assert.ok(recipientMessageAfterRevoke);
      const recipientVaultDataAfterRevoke = JSON.parse(
        recipientMessageAfterRevoke.Data,
      );
      assert.deepEqual(recipientVaultDataAfterRevoke, expectedVaultData);

      const controllerMessageAfterRevoke = result.Messages.find((msg) =>
        msg.Tags.find(
          (tag) => tag.name === 'Action' && tag.value === 'Credit-Notice',
        ),
      );
      assert.ok(controllerMessageAfterRevoke);
      const controllerVaultDataAfterRevoke = JSON.parse(
        controllerMessageAfterRevoke.Data,
      );
      assert.deepEqual(controllerVaultDataAfterRevoke, expectedVaultData);

      // Assert balance is back for controller
      const controllerBalanceAfter = await getBalance({
        address: controller,
        memory: result.Memory,
      });
      assert.deepEqual(controllerBalanceAfter, quantity);

      endingMemory = result.Memory;
    });

    it('should fail if the vault size is too small', async () => {
      const quantity = 99999999;
      const { result: createVaultedTransferResult } =
        await createVaultedTransfer({
          quantity,
          lockLengthMs,
          recipient,
          shouldAssertNoResultError: false,
          memory: sharedMemory,
        });

      const errorTag = createVaultedTransferResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert(
        errorTag.value.includes(
          'Invalid quantity. Must be integer greater than or equal to 100000000 mARIO',
        ),
      );
      endingMemory = createVaultedTransferResult.Memory;
    });

    it('should fail if the recipient address is invalid and Allow-Unsafe-Addresses is not provided', async () => {
      const recipient = 'invalid-address';
      const { result: createVaultedTransferResult } =
        await createVaultedTransfer({
          quantity,
          lockLengthMs,
          recipient,
          shouldAssertNoResultError: false,
          memory: sharedMemory,
        });

      const errorTag = createVaultedTransferResult.Messages?.[0]?.Tags?.find(
        (tag) => tag.name === 'Error',
      );
      assert.ok(errorTag);
      assert(errorTag.value.includes('Invalid recipient'));
      endingMemory = createVaultedTransferResult.Memory;
    });

    it('should create a vault for the recipient with an invalid address and Allow-Unsafe-Addresses is provided', async () => {
      const recipient = 'invalid-address';
      const msgId = 'unique-id-'.padEnd(43, 'a');
      const { result: createVaultedTransferResult } =
        await createVaultedTransfer({
          quantity,
          lockLengthMs,
          recipient,
          allowUnsafeAddresses: true,
          msgId,
          memory: sharedMemory,
        });

      const createdVaultData = await assertVaultExists({
        vaultId: msgId,
        address: recipient,
        memory: createVaultedTransferResult.Memory,
      });
      assert.deepEqual(createdVaultData.balance, quantity);
      assert.deepEqual(createdVaultData.startTimestamp, STUB_TIMESTAMP);
      assert.deepEqual(
        createdVaultData.endTimestamp,
        STUB_TIMESTAMP + lockLengthMs,
      );
      endingMemory = createVaultedTransferResult.Memory;
    });
  });

  describe('getPaginatedVaults', () => {
    let paginatedVaultMemory = sharedMemory; // save the memory
    const vaultId1 = 'unique-id-1-'.padEnd(43, 'a');
    const secondVaulter = 'unique-second-address-'.padEnd(43, 'a');
    const vaultId2 = 'unique-id-2-'.padEnd(43, 'a');

    before(async () => {
      const { memory: updatedMemory } = await createVault({
        quantity: 500000000,
        lockLengthMs: 1209600000,
        memory: sharedMemory,
        msgId: vaultId1,
      });

      const transferResult = await handle({
        options: {
          Tags: [
            { name: 'Action', value: 'Transfer' },
            { name: 'Recipient', value: secondVaulter },
            { name: 'Quantity', value: 600000000 },
            { name: 'Cast', value: true },
          ],
        },
        memory: updatedMemory,
      });

      const { memory: updatedMemory2 } = await createVault({
        quantity: 600000000,
        lockLengthMs: 1209600000,
        memory: transferResult.Memory,
        from: secondVaulter,
        msgId: vaultId2,
      });
      paginatedVaultMemory = updatedMemory2;
    });

    it('should get paginated vaults', async () => {
      let cursor = '';
      let fetchedVaults = [];
      while (true) {
        const { result: paginatedVaultsResult, memory } = await getVaults({
          memory: paginatedVaultMemory,
          cursor,
          limit: 1,
        });

        // parse items, nextCursor
        const { items, nextCursor, hasMore, sortBy, sortOrder, totalItems } =
          JSON.parse(paginatedVaultsResult.Messages?.[0]?.Data);

        assert.equal(totalItems, 2);
        assert.equal(items.length, 1);
        assert.equal(sortBy, 'address');
        assert.equal(sortOrder, 'desc');
        assert.equal(hasMore, !!nextCursor);
        cursor = nextCursor;
        fetchedVaults.push(...items);
        endingMemory = memory;
        if (!cursor) break;
      }

      assert.deepEqual(fetchedVaults, [
        {
          address: secondVaulter,
          vaultId: vaultId2,
          balance: 600000000,
          startTimestamp: 21600000,
          endTimestamp: 1231200000,
        },
        {
          address: PROCESS_OWNER,
          vaultId: vaultId1,
          balance: 500000000,
          startTimestamp: 21600000,
          endTimestamp: 1231200000,
        },
      ]);
    });

    it('should get paginated vaults sorted by ascending balance', async () => {
      let cursor = '';
      let fetchedVaults = [];
      while (true) {
        const { result: paginatedVaultsResult, memory } = await getVaults({
          memory: paginatedVaultMemory,
          cursor,
          limit: 1,
          sortBy: 'balance',
          sortOrder: 'asc',
        });

        // parse items, nextCursor
        const { items, nextCursor, hasMore, sortBy, sortOrder, totalItems } =
          JSON.parse(paginatedVaultsResult.Messages?.[0]?.Data);

        assert.equal(totalItems, 2);
        assert.equal(items.length, 1);
        assert.equal(sortBy, 'balance');
        assert.equal(sortOrder, 'asc');
        assert.equal(hasMore, !!nextCursor);
        cursor = nextCursor;
        fetchedVaults.push(...items);
        endingMemory = memory;
        if (!cursor) break;
      }

      assert.deepEqual(fetchedVaults, [
        {
          address: PROCESS_OWNER,
          vaultId: vaultId1,
          balance: 500000000,
          startTimestamp: 21600000,
          endTimestamp: 1231200000,
        },
        {
          address: secondVaulter,
          vaultId: vaultId2,
          balance: 600000000,
          startTimestamp: 21600000,
          endTimestamp: 1231200000,
        },
      ]);
    });
  });
});
