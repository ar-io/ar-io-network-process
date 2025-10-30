import {
  assertNoResultError,
  buyRecord,
  handle,
  startMemory,
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
});
