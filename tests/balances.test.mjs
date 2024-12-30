import { getBalance, getBalances, startMemory } from './helpers.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import { STUB_ADDRESS, PROCESS_OWNER } from '../tools/constants.mjs';

describe('Balances', async () => {
  it('should return the balance for a specific address', async () => {
    const balance = await getBalance({
      address: PROCESS_OWNER,
      memory: startMemory,
    });
    assert.equal(balance, 950000000000000);
  });

  it('should return 0 for a non-existent address', async () => {
    const balance = await getBalance({
      address: STUB_ADDRESS,
      memory: startMemory,
    });
    assert.equal(balance, 0);
  });

  it('should return dictionary of all balances', async () => {
    const balances = await getBalances({ memory: startMemory });
    assert.equal(balances[PROCESS_OWNER], 950000000000000);
  });
});
