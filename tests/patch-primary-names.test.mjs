import {
  assertNoResultError,
  buyRecord,
  handle,
  startMemory,
  tick,
  totalTokenSupply,
  transfer,
} from './helpers.mjs';
import assert from 'assert';
import { describe, it } from 'node:test';
import { STUB_TIMESTAMP } from '../tools/constants.mjs';

describe('Primary Names Hyperbeam Patching', function () {
  it('should send patch with request when primary name request is created', async () => {
    const testTimestamp = STUB_TIMESTAMP + 1000;
    const testCaller = 'test-caller-address-'.padEnd(43, '1');
    const baseNameOwner = 'base-name-owner-address-'.padEnd(43, '2');
    const testName = 'test-name';
    const testProcessId = 'test-process-id-'.padEnd(43, '1');

    // Initialize token supply
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    let memory = totalTokenSupplyMemory;

    // Give both addresses balance
    let result = await transfer({
      recipient: baseNameOwner,
      quantity: 10000000000,
      memory,
      timestamp: testTimestamp,
    });
    memory = result;

    result = await transfer({
      recipient: testCaller,
      quantity: 10000000000,
      memory,
      timestamp: testTimestamp + 10,
    });
    memory = result;

    // Base name owner buys the ArNS record
    result = await buyRecord({
      memory,
      from: baseNameOwner,
      name: testName,
      processId: testProcessId,
      type: 'permabuy',
      timestamp: testTimestamp + 100,
    });
    memory = result.memory;

    // Request primary name from a different caller than the base name owner
    const requestResult = await handle({
      options: {
        From: testCaller,
        Owner: testCaller,
        Timestamp: testTimestamp + 200,
        Tags: [
          { name: 'Action', value: 'Request-Primary-Name' },
          { name: 'Name', value: testName },
        ],
      },
      memory,
    });

    assertNoResultError(requestResult);

    // Find the patch message with device: "patch@1.0"
    const messages = requestResult.Messages || [];
    let patchMessage = null;
    for (let i = messages.length - 1; i >= 0; i--) {
      const tags = messages[i].Tags || [];
      const deviceTag = tags.find((t) => t.name === 'device');
      if (deviceTag && deviceTag.value === 'patch@1.0') {
        patchMessage = messages[i];
        break;
      }
    }

    assert(patchMessage, 'Should send a patch message');

    // Get the primary-names tag
    const primaryNamesTag = patchMessage.Tags.find(
      (t) => t.name === 'primary-names',
    );
    assert(primaryNamesTag, 'Patch should have primary-names tag');

    // Patch messages don't JSON-encode on purpose, so the value is already an object
    const patch = primaryNamesTag.value;

    assert(patch, 'Should have primary names patch data');
    assert(patch.requests, 'Patch should include requests');
    assert(
      patch.requests[testCaller],
      'Patch should include the request for the caller',
    );
    assert.strictEqual(
      patch.requests[testCaller].name,
      testName,
      'Request should have correct name',
    );
  });

  it('should handle sending a patch when pruning an expired primary name request', async () => {
    const testTimestamp = STUB_TIMESTAMP + 1000;
    const testCaller = 'test-caller-address-'.padEnd(43, '1');
    const baseNameOwner = 'base-name-owner-address-'.padEnd(43, '2');
    const testName = 'test-name';
    const testProcessId = 'test-process-id-'.padEnd(43, '1');

    // Initialize token supply
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    let memory = totalTokenSupplyMemory;

    // Give both addresses balance
    let result = await transfer({
      recipient: baseNameOwner,
      quantity: 10000000000,
      memory,
      timestamp: testTimestamp,
    });
    memory = result;

    result = await transfer({
      recipient: testCaller,
      quantity: 10000000000,
      memory,
      timestamp: testTimestamp + 10,
    });
    memory = result;

    // Base name owner buys the ArNS record
    result = await buyRecord({
      memory,
      from: baseNameOwner,
      name: testName,
      processId: testProcessId,
      type: 'permabuy',
      timestamp: testTimestamp + 100,
    });
    memory = result.memory;

    // Request primary name from a different caller than the base name owner
    const requestResult = await handle({
      options: {
        From: testCaller,
        Owner: testCaller,
        Timestamp: testTimestamp + 200,
        Tags: [
          { name: 'Action', value: 'Request-Primary-Name' },
          { name: 'Name', value: testName },
        ],
      },
      memory,
    });

    assertNoResultError(requestResult);
    memory = requestResult.Memory;

    // Advance time past request expiration (7 days + 1 ms)
    const primaryNameRequestDurationMs = 7 * 24 * 60 * 60 * 1000;
    const futureTimestamp =
      testTimestamp + 200 + primaryNameRequestDurationMs + 1;

    // Trigger pruning with a tick
    const { result: tickResult } = await tick({
      memory,
      timestamp: futureTimestamp,
    });

    // Verify patch message was sent with pruned request
    const patchMessage = tickResult.Messages.find((msg) =>
      msg.Tags.some(
        (tag) => tag.name === 'device' && tag.value === 'patch@1.0',
      ),
    );
    assert(patchMessage, 'Should send a patch message');

    const primaryNamesTag = patchMessage.Tags.find(
      (tag) => tag.name === 'primary-names',
    );
    assert(primaryNamesTag, 'Should include primary-names in patch');

    const patch = primaryNamesTag.value;
    assert(patch, 'Should have primary names patch data');
    assert('requests' in patch, 'Patch should include requests field');

    // When all requests are pruned (PrimaryNames.requests becomes empty),
    // the patch sends an empty array [] to signal "clear all requests from hyperbeam"
    // This is the correct behavior to sync the empty state
    assert.deepStrictEqual(
      patch.requests,
      [],
      'Pruned requests should result in an empty array when all requests are removed',
    );
  });

  it('should handle sending a patch when pruning some but not all primary name requests', async () => {
    const testTimestamp = STUB_TIMESTAMP + 1000;
    const testCaller1 = 'test-caller-address-'.padEnd(43, '1');
    const testCaller2 = 'test-caller-address-'.padEnd(43, '2');
    const baseNameOwner = 'base-name-owner-address-'.padEnd(43, '3');
    const testName1 = 'test-name-1';
    const testName2 = 'test-name-2';
    const testProcessId = 'test-process-id-'.padEnd(43, '1');

    // Initialize token supply
    const { Memory: totalTokenSupplyMemory } = await totalTokenSupply({
      memory: startMemory,
    });
    let memory = totalTokenSupplyMemory;

    // Give all addresses balance
    const addresses = [baseNameOwner, testCaller1, testCaller2];
    for (let i = 0; i < addresses.length; i++) {
      const result = await transfer({
        recipient: addresses[i],
        quantity: 10000000000,
        memory,
        timestamp: testTimestamp + i * 10,
      });
      memory = result;
    }

    // Base name owner buys two ArNS records
    const buyResult1 = await buyRecord({
      memory,
      from: baseNameOwner,
      name: testName1,
      processId: testProcessId,
      type: 'permabuy',
      timestamp: testTimestamp + 100,
    });
    memory = buyResult1.memory;

    const buyResult2 = await buyRecord({
      memory,
      from: baseNameOwner,
      name: testName2,
      processId: testProcessId,
      type: 'permabuy',
      timestamp: testTimestamp + 110,
    });
    memory = buyResult2.memory;

    // Create two primary name requests at different times
    const requestResult1 = await handle({
      options: {
        From: testCaller1,
        Owner: testCaller1,
        Timestamp: testTimestamp + 200,
        Tags: [
          { name: 'Action', value: 'Request-Primary-Name' },
          { name: 'Name', value: testName1 },
        ],
      },
      memory,
    });
    assertNoResultError(requestResult1);
    memory = requestResult1.Memory;

    // Create second request 1 day later
    const oneDayMs = 24 * 60 * 60 * 1000;
    const requestResult2 = await handle({
      options: {
        From: testCaller2,
        Owner: testCaller2,
        Timestamp: testTimestamp + 200 + oneDayMs,
        Tags: [
          { name: 'Action', value: 'Request-Primary-Name' },
          { name: 'Name', value: testName2 },
        ],
      },
      memory,
    });
    assertNoResultError(requestResult2);
    memory = requestResult2.Memory;

    // Advance time to prune only the first request (7 days after first request, but 6 days after second)
    const primaryNameRequestDurationMs = 7 * 24 * 60 * 60 * 1000;
    const futureTimestamp =
      testTimestamp + 200 + primaryNameRequestDurationMs + 1;

    // Trigger pruning with a tick
    const { result: tickResult } = await tick({
      memory,
      timestamp: futureTimestamp,
    });

    // Verify patch message was sent
    const patchMessage = tickResult.Messages.find((msg) =>
      msg.Tags.some(
        (tag) => tag.name === 'device' && tag.value === 'patch@1.0',
      ),
    );
    assert(patchMessage, 'Should send a patch message');

    const primaryNamesTag = patchMessage.Tags.find(
      (tag) => tag.name === 'primary-names',
    );
    assert(primaryNamesTag, 'Should include primary-names in patch');

    const patch = primaryNamesTag.value;
    assert(patch, 'Should have primary names patch data');
    assert(patch.requests, 'Patch should include requests');

    // When only some requests are pruned, the patch should include
    // the pruned address with an empty array (Lua's empty table {} becomes [] in JS)
    assert(
      testCaller1 in patch.requests,
      'Patch should include the first pruned request',
    );
    assert.deepStrictEqual(
      patch.requests[testCaller1],
      [],
      'Pruned request should be an empty array',
    );

    // The second request should not be in the patch since it wasn't pruned
    assert(
      !(testCaller2 in patch.requests),
      'Patch should not include the second request since it was not pruned',
    );
  });
});
