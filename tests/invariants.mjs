import assert from 'node:assert';
import { getBalances, getVaults } from './helpers.mjs';

function assertValidBalance(balance) {
  assert(
    balance >= 0 && balance <= 1_000_000_000_000_000,
    `Invariant violated: balance ${balance} is invalid`,
  );
}

function assertValidAddress(address) {
  assert(address.length > 0, `Invariant violated: address ${address} is empty`);
}

function assertValidTimestampsAtTimestamp({
  startTimestamp,
  endTimestamp,
  timestamp,
}) {
  assert(
    startTimestamp <= timestamp,
    `Invariant violated: startTimestamp ${startTimestamp} is in the future`,
  );
  assert(
    endTimestamp === null || endTimestamp >= startTimestamp,
    `Invariant violated: endTimestamp of ${endTimestamp} for vault ${address}`,
  );
}

export async function assertNoInvariants({ timestamp, memory }) {
  await assertNoBalanceInvariants({ timestamp, memory });
  await assertNoBalanceVaultInvariants({ timestamp, memory });
}

async function assertNoBalanceInvariants({ timestamp, memory }) {
  // Assert all balances are >= 0 and all belong to valid addresses
  const balances = await getBalances({
    memory,
    timestamp,
  });
  for (const [address, balance] of Object.entries(balances)) {
    assertValidBalance(balance);
    assertValidAddress(address);
  }
}

async function assertNoBalanceVaultInvariants({ timestamp, memory }) {
  const { result } = await getVaults({
    memory,
    limit: 1_000_000, // egregiously large limit to make sure we get them all
  });

  for (const vault of JSON.parse(result.Messages?.[0]?.Data).items) {
    const { address, balance, startTimestamp, endTimestamp } = vault;
    assertValidBalance(balance);
    assertValidAddress(address);
    assertValidTimestampsAtTimestamp({
      startTimestamp,
      endTimestamp,
      timestamp,
    });
  }
}
