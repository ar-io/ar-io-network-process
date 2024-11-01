import { createAosLoader } from './utils.mjs';
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  AO_LOADER_HANDLER_ENV,
  DEFAULT_HANDLE_OPTIONS,
  STUB_TIMESTAMP,
  STUB_MESSAGE_ID,
  STUB_ADDRESS,
  PROCESS_OWNER,
  PROCESS_ID,
} from '../tools/constants.mjs';
import * as handlers from './fixtures.test.mjs';

const stubbedTimestamp = STUB_TIMESTAMP + 1000 * 60 * 60 * 24 * 30; // 30 days after stubbedTimestamp
const initialOperatorStake = 100_000_000_000;

describe('GatewayRegistry', async () => {
  let sharedMemory;
  beforeEach(async () => {
    const { memory: transferMemory } = await handlers.transfer({
      recipient: STUB_ADDRESS,
      quantity: initialOperatorStake,
    });
    const { memory: joinNetworkMemory } = await handlers.joinNetwork({
      memory: transferMemory,
      address: STUB_ADDRESS,
    });
    // NOTE: all tests will start with this gateway joined to the network - use `sharedMemory` for the first interaction for each test to avoid having to join the network again
    sharedMemory = joinNetworkMemory;
  });

  describe('Join-Network', () => {
    it('should allow joining of the network record', async () => {
      // check the gateway record from contract
      const { gateway: gatewayData } = await handlers.getGateway({
        memory: sharedMemory,
        timestamp: STUB_TIMESTAMP + 1,
        address: STUB_ADDRESS,
      });
      console.log(gatewayData);
      assert.deepEqual(gatewayData, {
        observerAddress: STUB_ADDRESS,
        operatorStake: 100_000_000_000, // matches the initial operator stake from the test setup
        totalDelegatedStake: 0,
        status: 'joined',
        delegates: [],
        vaults: [],
        startTimestamp: STUB_TIMESTAMP,
        settings: {
          label: 'test-gateway',
          note: 'test-note',
          fqdn: 'test-fqdn',
          port: 443,
          protocol: 'https',
          allowDelegatedStaking: true,
          minDelegatedStake: 500_000_000,
          delegateRewardShareRatio: 25,
          properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
          autoStake: true,
        },
        stats: {
          passedConsecutiveEpochs: 0,
          failedConsecutiveEpochs: 0,
          totalEpochCount: 0,
          failedEpochCount: 0,
          passedEpochCount: 0,
          prescribedEpochCount: 0,
          observedEpochCount: 0,
        },
      });
    });
  });

  // describe('Leave-Network', () => {
  //   it('should allow leaving the network', async () => {
  //     const { memory: leaveNetworkMemory } =
  //       await handlers.leaveNetwork({ memory: sharedMemory });

  //     // check the gateway record from contract
  //     const { gateway: gatewayData } = await handlers.getGateway({
  //       memory: leaveNetworkMemory,
  //       timestamp: STUB_TIMESTAMP + 1,
  //       address: STUB_ADDRESS,
  //     });
  //     assert.deepStrictEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 0,
  //       totalDelegatedStake: 0,
  //       status: 'leaving',
  //       delegates: [],
  //       endTimestamp:
  //         leaveNetworkData.startTimestamp + 1000 * 60 * 60 * 24 * 90, // 90 days
  //       vaults: {
  //         [STUB_ADDRESS]: {
  //           balance: 50_000_000_000, // matches the minimum stake after the decrease
  //           startTimestamp: leaveNetworkData.startTimestamp,
  //           endTimestamp:
  //             leaveNetworkData.startTimestamp + 1000 * 60 * 60 * 24 * 90, // 90 days
  //         },
  //         [STUB_MESSAGE_ID]: {
  //           balance: 50_000_000_000, // all stake greater than the minimum stake and only vaulted for 30 days instead of 90
  //           startTimestamp: leaveNetworkData.startTimestamp,
  //           endTimestamp:
  //             leaveNetworkData.startTimestamp + 1000 * 60 * 60 * 24 * 30, // 30 days
  //         },
  //       },
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'test-gateway',
  //         note: 'test-note',
  //         fqdn: 'test-fqdn',
  //         port: 443,
  //         protocol: 'https',
  //         allowDelegatedStaking: true,
  //         minDelegatedStake: 500_000_000,
  //         delegateRewardShareRatio: 25,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //         autoStake: true,
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });
  //   });
  // });

  // describe('Update-Gateway-Settings', () => {
  //   it('should allow updating the gateway settings', async () => {
  //     const { memory: updateGatewaySettingsMemory } =
  //       await handlers.updateGatewaySettings({
  //         memory: sharedMemory,
  //         address: STUB_ADDRESS,
  //         settings: [
  //           { name: 'Label', value: 'new-label' },
  //         ],
  //       });

  //     // check the gateway record from contract
  //     const { gateway: gatewayData } = await handlers.getGateway({
  //       memory: updateGatewaySettingsMemory,
  //       timestamp: STUB_TIMESTAMP + 1,
  //       address: STUB_ADDRESS,
  //     });

  //     assert.deepEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 100_000_000_000, // matches the initial operator stake from the test setup
  //       totalDelegatedStake: 0,
  //       status: 'joined',
  //       delegates: [],
  //       vaults: [],
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'new-label',
  //         note: 'new-note',
  //         fqdn: 'new-fqdn',
  //         port: 80,
  //         protocol: 'https',
  //         autoStake: false,
  //         allowDelegatedStaking: false,
  //         minDelegatedStake: 1_000_000_000,
  //         delegateRewardShareRatio: 10,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });
  //   });
  // });

  // describe('Increase-Operator-Stake', () => {
  //   // join the network and then increase stake
  //   it('should allow increasing operator stake', async () => {
  //     const increaseStakeQuantity = 10_000_000_000;
  //     const { memory: increaseStakeMemory } = await increaseOperatorStake({
  //       quantity: increaseStakeQuantity,
  //       memory: sharedMemory,
  //       address: STUB_ADDRESS,
  //     });

  //     // check the gateway record from contract
  //     const { gateway: gatewayData } = await getGateway({
  //       memory: increaseStakeMemory,
  //       timestamp: STUB_TIMESTAMP + 1,
  //       address: STUB_ADDRESS,
  //     });
  //     assert.deepEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 100_000_000_000 + increaseStakeQuantity, // matches the initial operator stake from the test setup plus the increase
  //       totalDelegatedStake: 0,
  //       status: 'joined',
  //       delegates: [],
  //       vaults: [],
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'test-gateway',
  //         note: 'test-note',
  //         fqdn: 'test-fqdn',
  //         port: 443,
  //         protocol: 'https',
  //         allowDelegatedStaking: true,
  //         minDelegatedStake: 500_000_000,
  //         delegateRewardShareRatio: 25,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //         autoStake: true,
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });
  //   });
  // });

  // describe('Decrease-Operator-Stake', () => {
  //   // join the network and then increase stake
  //   it('should allow decreasing the operator stake as long as it is above the minimum', async () => {
  //     const decreaseStakeQuantity = 10_000_000_000;
  //     const { memory: decreaseStakeMemory, result: decreaseStakeResult } =
  //       await decreaseOperatorStake({
  //         quantity: decreaseStakeQuantity,
  //         memory: sharedMemory,
  //         address: STUB_ADDRESS,
  //       });

  //     const { gateway: gatewayData } = await getGateway({
  //       memory: decreaseStakeMemory,
  //       timestamp: STUB_TIMESTAMP + 1,
  //       address: STUB_ADDRESS,
  //     });
  //     assert.deepStrictEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 100_000_000_000 - decreaseStakeQuantity, // matches the initial operator stake from the test setup minus the decrease
  //       totalDelegatedStake: 0,
  //       status: 'joined',
  //       delegates: [],
  //       vaults: {
  //         [STUB_MESSAGE_ID]: {
  //           balance: decreaseStakeQuantity,
  //           startTimestamp: STUB_TIMESTAMP,
  //           endTimestamp: STUB_TIMESTAMP + 1000 * 60 * 60 * 24 * 30, // thirty days
  //         },
  //       },
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'test-gateway',
  //         note: 'test-note',
  //         fqdn: 'test-fqdn',
  //         port: 443,
  //         protocol: 'https',
  //         allowDelegatedStaking: true,
  //         minDelegatedStake: 500_000_000,
  //         delegateRewardShareRatio: 25,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //         autoStake: true,
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });

  //     const expeditedWithdrawalFeeTag =
  //       decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //         (tag) => tag.name === 'Expedited-Withdrawal-Fee',
  //       );
  //     const amountWithdrawnTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Amount-Withdrawn',
  //     );
  //     const penaltyRateTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Penalty-Rate',
  //     );
  //     assert.strictEqual(Number(amountWithdrawnTag?.value ?? '0'), 0);
  //     assert.strictEqual(Number(penaltyRateTag?.value ?? '0'), 0);
  //     assert.strictEqual(Number(expeditedWithdrawalFeeTag?.value ?? '0'), 0);
  //   });

  //   it('should allow decreasing the operator stake to the exact minimum stake value', async () => {
  //     const amountToWithdraw = 50_000_000_000; // matches the initial operator stake from the test setup minus the minimum stake

  //     // Execute the handler for decreasing operator stake to the minimum allowed stake
  //     const decreaseStakeResult = await handle(
  //       {
  //         From: STUB_ADDRESS,
  //         Owner: STUB_ADDRESS,
  //         Tags: [
  //           { name: 'Action', value: 'Decrease-Operator-Stake' },
  //           { name: 'Quantity', value: amountToWithdraw.toString() }, // Withdraw to reach the minimum stake
  //         ],
  //       },
  //       sharedMemory,
  //     );

  //     // Assert no error tag
  //     const errorTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Error',
  //     );
  //     assert.strictEqual(errorTag, undefined);

  //     // Parse and validate gateway data from the decreaseStakeResult message
  //     const gatewayData = JSON.parse(decreaseStakeResult.Messages[0].Data);

  //     assert.deepStrictEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 50_000_000_000, // matches the minimum stake after the decrease
  //       totalDelegatedStake: 0,
  //       status: 'joined',
  //       delegates: [],
  //       vaults: {
  //         [STUB_MESSAGE_ID]: {
  //           balance: amountToWithdraw,
  //           startTimestamp: STUB_TIMESTAMP,
  //           endTimestamp: STUB_TIMESTAMP + 1000 * 60 * 60 * 24 * 30, // thirty days
  //         },
  //       },
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'test-gateway',
  //         note: 'test-note',
  //         fqdn: 'test-fqdn',
  //         port: 443,
  //         protocol: 'https',
  //         allowDelegatedStaking: true,
  //         minDelegatedStake: 500_000_000,
  //         delegateRewardShareRatio: 25,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //         autoStake: true,
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });

  //     // Retrieve the tags from the response message
  //     const penaltyRateTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Penalty-Rate',
  //     );
  //     const expeditedWithdrawalFeeTag =
  //       decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //         (tag) => tag.name === 'Expedited-Withdrawal-Fee',
  //       );
  //     const amountWithdrawnTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Amount-Withdrawn',
  //     );

  //     // Assert that the tags exist and have the correct default values (0, since this is a regular decrease)
  //     assert(penaltyRateTag, 'Penalty-Rate tag should exist');
  //     assert.strictEqual(Number(penaltyRateTag.value), 0);

  //     assert(
  //       expeditedWithdrawalFeeTag,
  //       'Expedited-Withdrawal-Fee tag should exist',
  //     );
  //     assert.strictEqual(Number(expeditedWithdrawalFeeTag.value), 0);

  //     assert(amountWithdrawnTag, 'Amount-Withdrawn tag should exist');
  //     assert.strictEqual(Number(amountWithdrawnTag.value), 0);
  //   });

  //   it('should allow decreasing the operator stake with instant withdrawal to the exact minimum stake value', async () => {
  //     const amountToWithdraw = 50_000_000_000; // matches the minimum stake after the decrease

  //     // Execute the handler for decreasing operator stake with instant withdrawal to the minimum allowed stake
  //     const decreaseStakeResult = await handle(
  //       {
  //         From: STUB_ADDRESS,
  //         Owner: STUB_ADDRESS,
  //         Tags: [
  //           { name: 'Action', value: 'Decrease-Operator-Stake' },
  //           { name: 'Quantity', value: amountToWithdraw.toString() }, // Withdraw to reach the minimum stake
  //           { name: 'Instant', value: 'true' },
  //         ],
  //       },
  //       sharedMemory,
  //     );

  //     // Assert no error tag
  //     const errorTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Error',
  //     );
  //     assert.strictEqual(errorTag, undefined);

  //     // Parse and validate gateway data from the decreaseStakeResult message
  //     const gatewayData = JSON.parse(decreaseStakeResult.Messages[0].Data);
  //     assert.deepStrictEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 50_000_000_000, // matches the minimum stake after the decrease
  //       totalDelegatedStake: 0,
  //       status: 'joined',
  //       delegates: [],
  //       vaults: [],
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'test-gateway',
  //         note: 'test-note',
  //         fqdn: 'test-fqdn',
  //         port: 443,
  //         protocol: 'https',
  //         allowDelegatedStaking: true,
  //         minDelegatedStake: 500_000_000,
  //         delegateRewardShareRatio: 25,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //         autoStake: true,
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });

  //     // Retrieve the tags from the response message
  //     const penaltyRateTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Penalty-Rate',
  //     );
  //     const expeditedWithdrawalFeeTag =
  //       decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //         (tag) => tag.name === 'Expedited-Withdrawal-Fee',
  //       );
  //     const amountWithdrawnTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Amount-Withdrawn',
  //     );

  //     // Convert tag values to numbers for comparison
  //     const penaltyRate = Number(penaltyRateTag.value);
  //     const expeditedWithdrawalFee = Number(expeditedWithdrawalFeeTag.value);
  //     const amountWithdrawn = Number(amountWithdrawnTag.value);

  //     const expectedPenaltyRate = 0.5; // the maximum penalty rate for an expedited withdrawal
  //     assert.strictEqual(penaltyRate, expectedPenaltyRate);

  //     // Recalculate the expected values based on the penalty rate
  //     const expectedExpeditedWithdrawalFee =
  //       amountToWithdraw * expectedPenaltyRate;
  //     const expectedAmountWithdrawn =
  //       amountToWithdraw - expectedExpeditedWithdrawalFee;

  //     // Assert correct values for amount withdrawn and expedited withdrawal fee
  //     assert.strictEqual(amountWithdrawn, expectedAmountWithdrawn);
  //     assert.strictEqual(
  //       expeditedWithdrawalFee,
  //       expectedExpeditedWithdrawalFee,
  //     );
  //   });

  //   it('should allow decreasing the operator stake with instant withdrawal as long as it is above the minimum', async () => {
  //     const amountToWithdraw = 5_000_000_000;

  //     // Execute the handler for decreaseOperatorStake with instant withdrawal
  //     const decreaseStakeResult = await handle(
  //       {
  //         From: STUB_ADDRESS,
  //         Owner: STUB_ADDRESS,
  //         Tags: [
  //           { name: 'Action', value: 'Decrease-Operator-Stake' },
  //           { name: 'Quantity', value: amountToWithdraw.toString() }, // 5K IO
  //           { name: 'Instant', value: 'true' },
  //         ],
  //       },
  //       sharedMemory,
  //     );

  //     // Assert no error tag
  //     const errorTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Error',
  //     );
  //     assert.strictEqual(errorTag, undefined);

  //     // Parse and validate gateway data from the decreaseStakeResult message
  //     const gatewayData = JSON.parse(decreaseStakeResult.Messages[0].Data);
  //     assert.deepStrictEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 100_000_000_000 - amountToWithdraw, // matches the initial operator stake from the test setup minus the decrease
  //       totalDelegatedStake: 0,
  //       status: 'joined',
  //       delegates: [],
  //       vaults: [],
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'test-gateway',
  //         note: 'test-note',
  //         fqdn: 'test-fqdn',
  //         port: 443,
  //         protocol: 'https',
  //         allowDelegatedStaking: true,
  //         minDelegatedStake: 500_000_000,
  //         delegateRewardShareRatio: 25,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //         autoStake: true,
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });

  //     // Retrieve the tags from the response message
  //     const penaltyRateTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Penalty-Rate',
  //     );
  //     const expeditedWithdrawalFeeTag =
  //       decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //         (tag) => tag.name === 'Expedited-Withdrawal-Fee',
  //       );
  //     const amountWithdrawnTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.name === 'Amount-Withdrawn',
  //     );

  //     // Assert that the tags exist
  //     assert(penaltyRateTag, 'Penalty-Rate tag should exist');
  //     assert(
  //       expeditedWithdrawalFeeTag,
  //       'Expedited-Withdrawal-Fee tag should exist',
  //     );
  //     assert(amountWithdrawnTag, 'Amount-Withdrawn tag should exist');

  //     // Convert tag values to numbers for comparison
  //     const penaltyRate = Number(penaltyRateTag.value);
  //     const expeditedWithdrawalFee = Number(expeditedWithdrawalFeeTag.value);
  //     const amountWithdrawn = Number(amountWithdrawnTag.value);

  //     const expectedPenaltyRate = 0.5; // the maximum penalty rate for an expedited withdrawal
  //     const expectedExpeditedWithdrawalFee = Math.floor(
  //       amountToWithdraw * expectedPenaltyRate,
  //     );
  //     const expectedAmountWithdrawn =
  //       amountToWithdraw - expectedExpeditedWithdrawalFee;

  //     // Assert correct values for penalty rate, expedited withdrawal fee, and amount withdrawn
  //     assert.strictEqual(penaltyRate, expectedPenaltyRate);
  //     assert.strictEqual(amountWithdrawn, expectedAmountWithdrawn);
  //     assert.strictEqual(
  //       expeditedWithdrawalFee,
  //       expectedExpeditedWithdrawalFee,
  //     );
  //     // TODO: assert the penalty rate went to protocol and remainder went to wallet balance
  //   });

  //   it('should allow instantly withdrawing from an existing operator vault for a withdrawal fee', async () => {
  //     const decreaseStakeTimestamp = stubbedTimestamp + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
  //     const decreaseStakeQuantity = 5_000_000_000;
  //     const decreaseStakeResult = await handle(
  //       {
  //         From: STUB_ADDRESS,
  //         Owner: STUB_ADDRESS,
  //         Timestamp: decreaseStakeTimestamp,
  //         Id: ''.padEnd(43, 'x'),
  //         Tags: [
  //           { name: 'Action', value: 'Decrease-Operator-Stake' },
  //           { name: 'Quantity', value: decreaseStakeQuantity.toString() }, // 5K IO
  //         ],
  //       },
  //       sharedMemory,
  //     );

  //     // assert no error tag
  //     const errorTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.Name === 'Error',
  //     );
  //     assert.strictEqual(errorTag, undefined);

  //     const instantDecreaseStakeTimestamp =
  //       decreaseStakeTimestamp + 1000 * 60 * 60; // 60 minutes after stubbedTimestamp
  //     const instantOperatorWithdrawalResult = await handle(
  //       {
  //         From: STUB_ADDRESS,
  //         Owner: STUB_ADDRESS,
  //         Timestamp: instantDecreaseStakeTimestamp,
  //         Tags: [
  //           { name: 'Action', value: 'Instant-Withdrawal' },
  //           { name: 'Vault-Id', value: ''.padEnd(43, 'x') },
  //         ],
  //       },
  //       decreaseStakeResult.Memory,
  //     );

  //     // assert no error tag
  //     const withdrawalErrorTag =
  //       instantOperatorWithdrawalResult.Messages?.[0]?.Tags?.find(
  //         (tag) => tag.Name === 'Error',
  //       );
  //     assert.strictEqual(withdrawalErrorTag, undefined);

  //     // check the gateway record from contract
  //     const gateway = await handle(
  //       {
  //         Tags: [
  //           { name: 'Action', value: 'Gateway' },
  //           { name: 'Address', value: STUB_ADDRESS },
  //         ],
  //       },
  //       instantOperatorWithdrawalResult.Memory,
  //     );
  //     const gatewayData = JSON.parse(gateway.Messages[0].Data);
  //     assert.deepStrictEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 100_000_000_000 - decreaseStakeQuantity, // matches the initial operator stake from the test setup minus the decrease
  //       totalDelegatedStake: 0,
  //       status: 'joined',
  //       delegates: [],
  //       vaults: [],
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'test-gateway',
  //         note: 'test-note',
  //         fqdn: 'test-fqdn',
  //         port: 443,
  //         protocol: 'https',
  //         allowDelegatedStaking: true,
  //         minDelegatedStake: 500_000_000,
  //         delegateRewardShareRatio: 25,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //         autoStake: true,
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });
  //     // TODO: validate the instant withdrawal went to wallet balance
  //   });
  // });

  // describe('Delegate-Stake', () => {
  //   // transfer some tokens to different address
  //   const newStubAddress = ''.padEnd(43, '3');

  //   it('should allow delegating stake', async () => {
  //     const { memory } = await delegateStake({
  //       quantity: 2_000_000_000,
  //       sharedMemory,
  //     });

  //     // check the gateway record from contract
  //     const { gateway: gatewayData } = await getGateway({
  //       memory,
  //       address: STUB_ADDRESS,
  //     });

  //     assert.deepEqual(gatewayData.delegates, {
  //       [newStubAddress]: {
  //         delegatedStake: quantity,
  //         startTimestamp: STUB_TIMESTAMP + 1,
  //         vaults: [],
  //       },
  //     });
  //     assert.deepEqual(gatewayData.totalDelegatedStake, quantity);
  //   });

  //   it('should allow withdrawing stake from a gateway', async () => {
  //     // delegate the stake and then withdraw it
  //     const { memory } = await delegateStake({
  //       quantity: 2_000_000_000,
  //       sharedMemory,
  //     });

  //     const decreaseStakeTimestamp = STUB_TIMESTAMP + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
  //     const { memory: decreaseStakeMemory, vaultId } =
  //       await decreaseDelegateStake({
  //         quantity: 500_000_000,
  //         memory,
  //         timestamp: decreaseStakeTimestamp,
  //       });

  //     // get the gateway record
  //     const { gateway: gatewayData } = await getGateway({
  //       memory: decreaseStakeMemory,
  //       timestamp: decreaseStakeTimestamp + 1,
  //       address: STUB_ADDRESS,
  //     });

  //     assert.deepEqual(gatewayData.delegates, {
  //       [newStubAddress]: {
  //         delegatedStake: 1_500_000_000,
  //         startTimestamp: STUB_TIMESTAMP + 1,
  //         vaults: {
  //           [vaultId]: {
  //             balance: 500_000_000,
  //             startTimestamp: decreaseStakeTimestamp, // 15 minutes after stubbedTimestamp
  //             endTimestamp: decreaseStakeTimestamp + 1000 * 60 * 60 * 24 * 30, // 30 days
  //           },
  //         },
  //       },
  //     });
  //     assert.deepEqual(gatewayData.totalDelegatedStake, 1_500_000_000);
  //   });

  //   it('should allow cancelling a delegate withdrawal', async () => {
  //     const { memory } = await delegateStake({
  //       quantity: 2_000_000_000,
  //       sharedMemory,
  //     });
  //     const cancelWithdrawalTimestamp = STUB_TIMESTAMP + 1000 * 60 * 30; // 30 minutes after stubbedTimestamp
  //     const cancelWithdrawalResult = await handle(
  //       {
  //         From: newStubAddress,
  //         Owner: newStubAddress,
  //         Tags: [
  //           { name: 'Action', value: 'Cancel-Withdrawal' },
  //           { name: 'Address', value: STUB_ADDRESS },
  //           { name: 'Vault-Id', value: ''.padEnd(43, 'x') },
  //         ],
  //         Timestamp: cancelWithdrawalTimestamp,
  //       },
  //       memory,
  //     );

  //     const { gateway: gatewayData } = await getGateway({
  //       memory: cancelWithdrawalResult.Memory,
  //       timestamp: cancelWithdrawalTimestamp + 1,
  //       address: STUB_ADDRESS,
  //     });

  //     assert.deepEqual(gatewayData.delegates, {
  //       [newStubAddress]: {
  //         delegatedStake: 2_000_000_000,
  //         startTimestamp: STUB_TIMESTAMP + 1,
  //         vaults: [],
  //       },
  //     });
  //     assert.deepEqual(gatewayData.totalDelegatedStake, 2_000_000_000);
  //   });
  // });

  // describe('Decrease-Delegate-Stake', () => {
  //   it('should allow decrease delegate stake from a gateway followed up with instant withdrawal', async () => {
  //     const decreaseStakeTimestamp = stubbedTimestamp + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
  //     const decreaseStakeResult = await handle(
  //       {
  //         From: newStubAddress,
  //         Owner: newStubAddress,
  //         Timestamp: decreaseStakeTimestamp,
  //         Id: ''.padEnd(43, 'x'),
  //         Tags: [
  //           { name: 'Action', value: 'Decrease-Delegate-Stake' },
  //           { name: 'Address', value: STUB_ADDRESS },
  //           { name: 'Quantity', value: `${1_000_000_000}` }, // 1K IO
  //         ],
  //       },
  //       delegateSharedMemory, // use the original shared memory containing a gateway with a delegate and a canceled withdrawal (i.e. no vaults)
  //     );

  //     // assert no error tag
  //     const errorTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.Name === 'Error',
  //     );
  //     assert.strictEqual(errorTag, undefined);

  //     // withdraw period is 30 days, so jump to 15 days later resulting in a 30% penalty rate
  //     const instantWithdrawalTimestamp =
  //       decreaseStakeTimestamp + 1000 * 60 * 60 * 24 * 15;
  //     const instantWithdrawalResult = await handle(
  //       {
  //         From: newStubAddress,
  //         Owner: newStubAddress,
  //         Timestamp: instantWithdrawalTimestamp,
  //         Tags: [
  //           { name: 'Action', value: 'Instant-Withdrawal' },
  //           { name: 'Address', value: STUB_ADDRESS },
  //           { name: 'Vault-Id', value: ''.padEnd(43, 'x') },
  //         ],
  //       },
  //       decreaseStakeResult.Memory,
  //     );

  //     console.log(instantWithdrawalResult);

  //     // assert no error tag
  //     const withdrawalErrorTag =
  //       instantWithdrawalResult.Messages?.[0]?.Tags?.find(
  //         (tag) => tag.Name === 'Error',
  //       );
  //     assert.strictEqual(withdrawalErrorTag, undefined);

  //     // get the gateway record
  //     const gateway = await handle(
  //       {
  //         Tags: [
  //           { name: 'Action', value: 'Gateway' },
  //           { name: 'Address', value: STUB_ADDRESS },
  //         ],
  //       },
  //       instantWithdrawalResult.Memory,
  //     );

  //     const gatewayData = JSON.parse(gateway.Messages[0].Data);
  //     assert.deepEqual(gatewayData.delegates, []);
  //     assert.deepEqual(gatewayData.totalDelegatedStake, 0);
  //     // validate the withdrawal went to the delegate balance and the penalty went to the protocol
  //     const balances = await handle(
  //       {
  //         Tags: [{ name: 'Action', value: 'Balances' }],
  //       },
  //       instantWithdrawalResult.Memory,
  //     );
  //     const expectedDelegateBalance = 1_000_000_000 * 0.7; // 70% of the original stake
  //     const expectedProtocolBalance = 1_000_000_000 * 0.3 + 50_000_000_000_000; // 30% of the original stake + original balance
  //     const balancesData = JSON.parse(balances.Messages[0].Data);
  //     assert.deepEqual(balancesData[newStubAddress], expectedDelegateBalance);
  //     assert.deepEqual(balancesData[PROCESS_ID], expectedProtocolBalance);
  //   });
  // });

  // describe('Cancel-Withdrawal', () => {
  //   it('should allow canceling a gateway withdrawal', async () => {
  //     const decreaseStakeTimestamp = stubbedTimestamp + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
  //     const decreaseStakeQuantity = 5_000_000_000;
  //     const { memory: decreaseStakeMemory, vaultId } =
  //       await handlers.decreaseOperatorStake({
  //         quantity: decreaseStakeQuantity,
  //         memory: sharedMemory,
  //     });

  //     const cancelWithdrawalTimestamp = decreaseStakeTimestamp + 1000 * 60 * 60; // 60 minutes after stubbedTimestamp
  //     const cancelWithdrawalResult = await handlers.cancelWithdrawal({
  //       memory: decreaseStakeMemory,
  //       timestamp: cancelWithdrawalTimestamp,
  //       address: STUB_ADDRESS,
  //       vaultId,
  //     });

  //     const { gateway: gatewayData } = await handlers.getGateway({
  //       memory: cancelWithdrawalResult.memory,
  //       timestamp: cancelWithdrawalTimestamp + 1,
  //       address: STUB_ADDRESS,
  //     });
  //     assert.deepStrictEqual(gatewayData, {
  //       observerAddress: STUB_ADDRESS,
  //       operatorStake: 100_000_000_000, // matches the initial operator stake from the test setup
  //       totalDelegatedStake: 0,
  //       status: 'joined',
  //       delegates: [],
  //       vaults: [],
  //       startTimestamp: STUB_TIMESTAMP,
  //       settings: {
  //         label: 'test-gateway',
  //         note: 'test-note',
  //         fqdn: 'test-fqdn',
  //         port: 443,
  //         protocol: 'https',
  //         allowDelegatedStaking: true,
  //         minDelegatedStake: 500_000_000,
  //         delegateRewardShareRatio: 25,
  //         properties: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  //         autoStake: true,
  //       },
  //       stats: {
  //         passedConsecutiveEpochs: 0,
  //         failedConsecutiveEpochs: 0,
  //         totalEpochCount: 0,
  //         failedEpochCount: 0,
  //         passedEpochCount: 0,
  //         prescribedEpochCount: 0,
  //         observedEpochCount: 0,
  //       },
  //     });
  //   });
  // });

  // describe('Instant-Withdrawal', () => {
  //   it('should allow a vaulted delegated stake to be instantly withdrawn', async () => {
  //     const instantWithdrawalTimestamp = stubbedTimestamp + 1000 * 60 * 15; // 15 minutes after stubbedTimestamp
  //     const decreaseStakeResult = await handle(
  //       {
  //         From: newStubAddress,
  //         Owner: newStubAddress,
  //         Timestamp: instantWithdrawalTimestamp,
  //         Id: ''.padEnd(43, 'x'),
  //         Tags: [
  //           { name: 'Action', value: 'Decrease-Delegate-Stake' },
  //           { name: 'Address', value: STUB_ADDRESS },
  //           { name: 'Quantity', value: `${1_000_000_000}` }, // 1K IO
  //           { name: 'Instant', value: 'true' },
  //         ],
  //       },
  //       sharedMemory, // use the original shared memory containing a gateway with a delegate
  //     );

  //     // assert no error tag
  //     const errorTag = decreaseStakeResult.Messages?.[0]?.Tags?.find(
  //       (tag) => tag.Name === 'Error',
  //     );
  //     assert.strictEqual(errorTag, undefined);

  //     // get the updated gateway record
  //     const gateway = await handle(
  //       {
  //         Tags: [
  //           { name: 'Action', value: 'Gateway' },
  //           { name: 'Address', value: STUB_ADDRESS },
  //         ],
  //         Timestamp: instantWithdrawalTimestamp + 1,
  //       },
  //       decreaseStakeResult.Memory,
  //     );
  //     const gatewayData = JSON.parse(gateway.Messages[0].Data);
  //     // Assertions
  //     assert.deepStrictEqual(gatewayData.delegates, {
  //       [newStubAddress]: {
  //         delegatedStake: 1_000_000_000,
  //         startTimestamp: STUB_TIMESTAMP + 1,
  //         vaults: [],
  //       },
  //     });
  //     assert.deepEqual(gatewayData.totalDelegatedStake, 1_000_000_000);
  //     // validate the withdrawal went to the delegate balance and the penalty went to the protocol
  //     const balances = await handle(
  //       {
  //         Tags: [{ name: 'Action', value: 'Balances' }],
  //       },
  //       decreaseStakeResult.Memory,
  //     );
  //     const balancesData = JSON.parse(balances.Messages[0].Data);
  //     const expectedDelegateBalance = 1_000_000_000 * 0.5; // half the original stake
  //     const expectedProtocolBalance = 1_000_000_000 * 0.5 + 50_000_000_000_000; // half the original stake + original balance
  //     assert.deepEqual(balancesData[newStubAddress], expectedDelegateBalance); // half the penalty
  //     assert.deepEqual(balancesData[PROCESS_ID], expectedProtocolBalance); // original stake + penalty
  //     // do not update shared memory
  //   });
  // });
  // // save observations
  // describe('Save-Observations', () => {
  //   it('should save observations', async () => {
  //     // Steps: add a gateway, create the first epoch to prescribe it, submit an observation from the gateway, tick to the epoch distribution timestamp, check the rewards were distributed correctly
  //   });
  // });
});
