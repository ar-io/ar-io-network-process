import { handle } from './helpers.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
} from '../tools/constants.mjs';

describe('handlers', async () => {
  it('should maintain order of handlers, with _eval and _default first, followed by prune', async () => {
    const handlers = await handle({
      options: {
        Tags: [
          {
            name: 'Action',
            value: 'Info',
          },
        ],
      },
    });
    const { Handlers: handlersList } = JSON.parse(handlers.Messages[0].Data);
    assert.ok(handlersList.includes('_eval'));
    assert.ok(handlersList.includes('_default'));
    assert.ok(handlersList.includes('prune'));

    const evalIndex = handlersList.indexOf('_eval');
    const defaultIndex = handlersList.indexOf('_default');
    const pruneIndex = handlersList.indexOf('prune');
    const expectedHandlerCount = 72; // TODO: update this if more handlers are added
    assert.ok(evalIndex === 0);
    assert.ok(defaultIndex === 1);
    assert.ok(pruneIndex === 2);
    assert.ok(
      handlersList.length === expectedHandlerCount,
      'should have ' +
        expectedHandlerCount +
        ' handlers; got ' +
        handlersList.length,
    ); // forces us to think critically about the order of handlers so intended to be sensitive to changes
  });

  describe('total supply', () => {
    describe('Total-Supply', () => {
      it('should compute the total supply and return just the total supply', async () => {
        const tokenSupplyResult = await handle({
          options: {
            Tags: [
              {
                name: 'Action',
                value: 'Total-Supply',
              },
            ],
          },
        });
        const tokenSupplyData = JSON.parse(
          tokenSupplyResult.Messages?.[0]?.Data,
        );
        assert.ok(tokenSupplyData === 1000000000 * 1000000);
      });
    });

    describe('Total-Token-Supply', () => {
      it('should compute the total supply and be equal to 1B IO, and return all the supply data', async () => {
        const supplyResult = await handle({
          options: {
            Tags: [
              {
                name: 'Action',
                value: 'Total-Token-Supply',
              },
            ],
          },
        });

        // assert no errors
        assert.deepEqual(supplyResult.Messages?.[0]?.Error, undefined);
        // assert correct tag in message by finding the index of the tag in the message
        const notice = supplyResult.Messages?.[0]?.Tags?.find(
          (tag) =>
            tag.name === 'Action' && tag.value === 'Total-Token-Supply-Notice',
        );
        assert.ok(notice, 'should have a Total-Token-Supply-Notice tag');

        const supplyData = JSON.parse(supplyResult.Messages?.[0]?.Data);

        assert.ok(
          supplyData.total === 1000000000 * 1000000,
          'total supply should be 1 billion IO but was ' + supplyData.total,
        );
        assert.ok(
          supplyData.circulating === 1000000000 * 1000000 - 50000000000000,
          'circulating supply should be 0.95 billion IO but was ' +
            supplyData.circulating,
        );
        assert.ok(
          supplyData.locked === 0,
          'locked supply should be 0 but was ' + supplyData.locked,
        );
        assert.ok(
          supplyData.staked === 0,
          'staked supply should be 0 but was ' + supplyData.staked,
        );
        assert.ok(
          supplyData.delegated === 0,
          'delegated supply should be 0 but was ' + supplyData.delegated,
        );
        assert.ok(
          supplyData.withdrawn === 0,
          'withdrawn supply should be 0 but was ' + supplyData.withdrawn,
        );

        assert.ok(
          supplyData.protocolBalance === 50000000000000,
          'protocol balance should be 50M IO but was ' +
            supplyData.protocolBalance,
        );
      });
    });
  });
});
