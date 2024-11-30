import assert from 'node:assert';
import { getBalances } from './helpers.mjs';

export async function assertNoInvariants({ timestamp, memory }) {
  // Assert all balances are >= 0 and all belong to valid addresses
  const balances = await getBalances({
    memory,
    timestamp,
  });
  for (const [address, balance] of Object.entries(balances)) {
    assert(
      balance >= 0 && balance <= 1_000_000_000_000_000,
      `Invariant violated: balance of ${balance} for address ${address}`,
    );
    assert(
      address.length > 0,
      `Invariant violated: address ${address} is empty`,
    );
  }
}
