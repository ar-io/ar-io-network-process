/**
 * Test suite for ARNS record pruning functionality
 *
 * The following tests share a memory buffer and validate:
 *
 * - Purchase 5 records as leases with different expiration years
 * - Validate the initial global pruning timestamp is set to the lowest records prune timestamp
 * - Validate the records exist in state until their grace period ends
 * - Validate a non-tick, write interaction (that updates the array buffer) properly triggers the pruning
 * - Validate event data is emitted when a record enters its grace period, and when it is pruned
 * - Validate records are pruned after the grace period ends
 * - Validate the global pruning timestamp is updated to the next records prune timestamp
 */
import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import {
  getRecord,
  startMemory,
  buyRecord,
  getPruningTimestamps,
  tick,
  getInfo,
  parseEventsFromResult,
} from './helpers.mjs';

const STUB_TIMESTAMP = 1706814747000; // Jan 1 2024
const oneYearMs = 365 * 24 * 60 * 60 * 1000;
const twoWeeksMs = 14 * 24 * 60 * 60 * 1000;

describe('ARNS Record Pruning', () => {
  let sharedMemory = startMemory;

  it('should prune expired records after grace period', async () => {
    // Purchase 5 records with different expiration years
    const names = ['name1', 'name2', 'name3', 'name4', 'name5'];
    const years = [1, 2, 3, 4, 5];

    for (let i = 0; i < names.length; i++) {
      const purchase = await buyRecord({
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP,
        name: names[i],
        years: years[i],
        type: 'lease',
      });
      sharedMemory = purchase.memory;
    }

    // validate the pruning timestamp is the minimum of all the timestamps + 2 week grace period
    const { records: recordsPruningTimestamp } = await getPruningTimestamps({
      memory: sharedMemory,
      timestamp: STUB_TIMESTAMP,
    });

    const expectedNextRecordsPruneTimestamp = STUB_TIMESTAMP + oneYearMs;
    assert.equal(
      recordsPruningTimestamp,
      expectedNextRecordsPruneTimestamp,
      `Expected pruning timestamp to be the minimum of existing record endTimestamps. Actual: ${new Date(recordsPruningTimestamp).toLocaleString()}. Expected: ${new Date(expectedNextRecordsPruneTimestamp).toLocaleString()}`,
    );

    // validate the record is reported event data includes in grace period records once record expires
    const gracePeriodStartInfoResult = await getInfo({
      memory: sharedMemory,
      timestamp: expectedNextRecordsPruneTimestamp + 1,
    });
    const [gracePeriodStartEvent] = parseEventsFromResult(
      gracePeriodStartInfoResult.result,
    );
    assert.equal(
      gracePeriodStartEvent['New-Grace-Period-Records-Count'],
      1,
      'Expected 1 record to be marked as in grace period',
    );
    assert.deepEqual(gracePeriodStartEvent['New-Grace-Period-Records'], [
      names[0],
    ]);
    sharedMemory = gracePeriodStartInfoResult.memory;

    // send an info request to trigger the pruning when the grace period ends
    const actualPruneTimestamp = expectedNextRecordsPruneTimestamp + twoWeeksMs;
    const infoResult = await getInfo({
      memory: sharedMemory,
      timestamp: actualPruneTimestamp,
    });
    sharedMemory = infoResult.memory;

    // parse the output event data to validate the name was pruned
    const [eventOutput] = parseEventsFromResult(infoResult.result);
    const prunedRecordsCount = eventOutput['Pruned-Records-Count'];
    assert.equal(prunedRecordsCount, 1, 'Expected 1 record to be pruned');
    const prunedRecords = eventOutput['Pruned-Records'];
    assert.equal(prunedRecords.length, 1, 'Expected 1 record to be pruned');
    assert.equal(
      prunedRecords[0],
      names[0],
      'Expected the first record to be pruned',
    );

    // check the pruning timestamp is updated after the tick
    const { records: updatedRecordsPruningTimestamp } =
      await getPruningTimestamps({
        memory: sharedMemory,
        timestamp: actualPruneTimestamp,
      });

    // validate the pruning timestamp is updated to the next records prune timestamp
    const newRecordsPruningTimestamp = STUB_TIMESTAMP + 2 * oneYearMs;
    assert.equal(
      updatedRecordsPruningTimestamp,
      newRecordsPruningTimestamp,
      `Expected pruning timestamp to be the minimum of existing record endTimestamps. Actual: ${new Date(recordsPruningTimestamp).toLocaleString()}. Expected: ${new Date(newRecordsPruningTimestamp).toLocaleString()}`,
    );

    // Record should be pruned after grace period
    const postGraceRecord = await getRecord({
      memory: sharedMemory,
      name: names[0],
      timestamp: actualPruneTimestamp + 1,
    });

    assert.equal(
      postGraceRecord,
      null,
      `Record ${names[0]} should be pruned after grace period`,
    );
  });
});
