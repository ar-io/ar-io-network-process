import { connect } from '@permaweb/aoconnect';

const arioProcessId =
  process.env.ARIO_NETWORK_PROCESS_ID ||
  'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE';

// TODO: add back in when we have a local ao-cu that can be used for testing this - as is we need results cached
const suRouter = process.env.SU_ROUTER || 'https://su-router.ao-testnet.xyz';
const ao = connect({
  CU_URL: process.env.CU_URL || 'http://cu.ardrive.io',
});

// get all messages for a process by action from a given timestamp
async function getMessagesForProcessByAction({
  processId,
  fromTimestamp,
  action,
}) {
  const res = await fetch(
    `${suRouter}/${processId}?from=${fromTimestamp.toString()}&limit=10000`,
    {
      method: 'GET',
    },
  );

  const data = await res.json();

  return data.edges
    .filter((edge) => {
      const actionValue = edge.node.message.tags.find(
        (t) => t.name === 'Action',
      )?.value;
      return actionValue === action;
    })
    .map((edge) => edge.node.message.id);
}

/**
 * Get all scheduled messages for a process
 * this is used to validate the cranking chain
 * @param {string} processId - The process ID to get scheduled messages for
 * @param {string} fromTimestamp - The timestamp to start from
 * @param {string} fromProcessId - The process ID of the sender
 * @param {string[]} references - The references to filter by
 * @returns {Promise<Record<string, string | null>>} - A map of references to message IDs
 */
async function mapReferencesToMessages({
  processId,
  fromTimestamp,
  fromProcessId,
  references,
}) {
  const res = await fetch(
    `${suRouter}/${processId}?from=${fromTimestamp}&limit=10000`,
    {
      method: 'GET',
    },
  );

  const data = await res.json();

  const referencesToMessages = references.reduce((acc, ref) => {
    acc[ref] = null;
    return acc;
  }, {});

  data.edges.forEach((edge) => {
    const fromProcess = edge.node.message.tags.find(
      (t) => t.name === 'From-Process',
    )?.value;
    if (fromProcess !== fromProcessId) return;

    const ref = edge.node.message.tags.find(
      (t) => t.name === '_Ref' || t.name === 'Reference',
    )?.value;
    if (!ref) return;

    if (references.includes(ref)) {
      referencesToMessages[ref] = edge.node.message.id;
    }
  });
  return referencesToMessages;
}

/**
 * Validate the cranking chain for a given message
 * @param {string} originMessageId - The message ID to validate
 * @param {string} fromTimestamp - The timestamp to start from
 * @returns {Promise<Record<string, string | null>>} - A map of references to message IDs
 */
async function validateCrankingChain({ originMessageId, fromTimestamp }) {
  const results = await ao.result({
    message: originMessageId,
    process: arioProcessId,
  });
  const messages = results.Messages;

  const targetsToReferences = messages.reduce((acc, m) => {
    const ref = m.Tags.find(
      (t) => t.name === '_Ref' || t.name === 'Reference',
    )?.value;
    if (!ref) return acc;
    return { ...acc, [m.Target]: [...(acc[m.Target] ?? []), ref] };
  }, {});

  const referencesToMessages = {};

  await Promise.all(
    Object.entries(targetsToReferences).map(async ([processId, references]) => {
      const res = await mapReferencesToMessages({
        processId,
        fromTimestamp,
        fromProcessId: arioProcessId,
        references,
      }).catch((e) => {
        // if the process is not found, we can ignore it as its likely a user not a process
        return;
      });
      if (!res) return;
      Object.entries(res).forEach(([ref, messageId]) => {
        referencesToMessages[ref] = messageId;
      });
    }),
  );
  return referencesToMessages;
}

async function main() {
  // Get the last checked timestamp
  const currentTimestamp = Date.now().toString();
  const oneDayMs = 24 * 60 * 60 * 1000;
  // check the last 24 hours worth of messages
  // TODO: save the last checked timestamp and persist across github actions jobs
  const lastCheckedTimestamp = (currentTimestamp - oneDayMs).toString();

  // Your existing logic to fetch and check transfer messages
  const transferMessages = await getMessagesForProcessByAction({
    processId: arioProcessId,
    fromTimestamp: lastCheckedTimestamp,
    action: 'Transfer',
  });

  const messageStatuses = transferMessages.reduce(async (acc, messageId) => {
    acc[messageId] = null;
    return acc;
  }, {});

  const failedCrankings = new Map();

  await Promise.all(
    transferMessages.map(async (originMessageId) => {
      // sets the references to messages for the origin message. Null means the reference was not found/cranked.
      messageStatuses[originMessageId] = await validateCrankingChain({
        originMessageId: originMessageId,
        fromTimestamp: lastCheckedTimestamp.toString(),
      });
      Object.entries(messageStatuses[originMessageId]).forEach(
        ([ref, messageId]) => {
          if (!messageId) {
            // discoverable using From-Process and Reference tags (in this case arioProcessId and ref)
            failedCrankings.set(originMessageId, ref);
          }
        },
      );
    }),
  );

  if (failedCrankings.size > 0) {
    console.error(
      'Failed Crankings',
      Array.from(failedCrankings).map(
        ([originMessageId, ref]) =>
          `Origin Message ID: ${originMessageId}, Ref: ${ref}`,
      ),
    );
    throw new Error('Failed Crankings');
  }
}

main()
  .then(async () => {
    process.exit('0');
  })
  .catch(async (e) => {
    console.error(e);
    process.exit('1');
  });
