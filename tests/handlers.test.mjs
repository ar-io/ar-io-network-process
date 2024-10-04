import { createAosLoader } from './utils.mjs';
import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
} from '../tools/constants.mjs';

describe('handlers', async () => {
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

  it('should maintain order of handlers, with _eval and _default first, followed by prune', async () => {
    const handlers = await handle({
      Tags: [
        {
          name: 'Action',
          value: 'Info',
        },
      ],
    });
    const { Handlers: handlersList } = JSON.parse(handlers.Messages[0].Data);
    assert.ok(handlersList.includes('_eval'));
    assert.ok(handlersList.includes('_default'));
    assert.ok(handlersList.includes('prune'));

    const evalIndex = handlersList.indexOf('_eval');
    const defaultIndex = handlersList.indexOf('_default');
    const pruneIndex = handlersList.indexOf('prune');
    const expectedHandlerCount = 50; // TODO: update this if more handlers are added
    assert.ok(evalIndex === 0);
    assert.ok(defaultIndex === 1);
    assert.ok(pruneIndex === 2);
    assert.ok(
      handlersList.length === expectedHandlerCount,
      'should only have 3 handlers',
    ); // forces us to think critically about the order of handlers so intended to be sensitive to changes
  });
});
