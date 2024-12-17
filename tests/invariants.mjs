import assert from 'node:assert';
import { getBalances, getVaults, handle } from './helpers.mjs';

function assertValidBalance(balance, expectedMin = 1) {
  assert(
    Number.isInteger(balance) &&
      balance >= expectedMin &&
      balance <= 1_000_000_000_000_000,
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
    endTimestamp === null || endTimestamp > startTimestamp,
    `Invariant violated: endTimestamp of ${endTimestamp} for vault ${address}`,
  );
}

async function assertNoBalanceInvariants({ timestamp, memory }) {
  // Assert all balances are >= 0 and all belong to valid addresses
  const balances = await getBalances({
    memory,
    timestamp,
  });
  for (const [address, balance] of Object.entries(balances)) {
    assertValidBalance(balance, 0);
    assertValidAddress(address);
  }
}

async function assertNoBalanceVaultInvariants({ timestamp, memory }) {
  const { result } = await getVaults({
    memory,
    limit: 1_000_000, // egregiously large limit to make sure we get them all
    timestamp,
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

async function assertNoTotalSupplyInvariants({ timestamp, memory }) {
  const supplyResult = await handle({
    options: {
      Tags: [
        {
          name: 'Action',
          value: 'Total-Token-Supply',
        },
      ],
      Timestamp: timestamp,
    },
    memory,
  });

  // assert no errors
  assert.deepEqual(supplyResult.Messages?.[0]?.Error, undefined);
  // assert correct tag in message by finding the index of the tag in the message
  const notice = supplyResult.Messages?.[0]?.Tags?.find(
    (tag) => tag.name === 'Action' && tag.value === 'Total-Token-Supply-Notice',
  );
  assert.ok(notice, 'should have a Total-Token-Supply-Notice tag');

  const supplyData = JSON.parse(supplyResult.Messages?.[0]?.Data);

  assert.ok(
    supplyData.total === 1000000000 * 1000000,
    'total supply should be 1,000,000,000,000,000 mARIO but was ' +
      supplyData.total,
  );
  assertValidBalance(supplyData.circulating, 0);
  assertValidBalance(supplyData.locked, 0);
  assertValidBalance(supplyData.staked, 0);
  assertValidBalance(supplyData.delegated, 0);
  assertValidBalance(supplyData.withdrawn, 0);
  assertValidBalance(supplyData.protocolBalance, 0);
}

// TODO: Add Gateway invariants
// async function assertNoGatewayInvariants( { timestamp, memory } ) {
//   const gatewayResult = await handle({
//     Tags: [
//       {
//         name: 'Action',
//         value: 'Gateway',
//       },
//     ],
//     Timestamp: timestamp,
//   }, memory);

//   // assert no errors
//   assert.deepEqual(gatewayResult.Messages?.[0]?.Error, undefined);
//   // assert correct tag in message by finding the index of the tag in the message
//   const notice = gatewayResult.Messages?.[0]?.Tags?.find(
//     (tag) => tag.name === 'Action' && tag.value === 'Gateway-Notice',
//   );
//   assert.ok(notice, 'should have a Gateway-Notice tag');

//   const gatewayData = JSON.parse(gatewayResult.Messages?.[0]?.Data);

//   assertValidBalance(gatewayData.total, 0);
//   assertValidBalance(gatewayData.locked, 0);
//   assertValidBalance(gatewayData.staked, 0);
//   assertValidBalance(gatewayData.delegated, 0);
//   assertValidBalance(gatewayData.withdrawn, 0);
//   assertValidBalance(gatewayData.protocolBalance, 0);
// }

export async function assertNoInvariants({ timestamp, memory }) {
  await assertNoBalanceInvariants({ timestamp, memory });
  await assertNoBalanceVaultInvariants({ timestamp, memory });
  await assertNoTotalSupplyInvariants({ timestamp, memory });
}
