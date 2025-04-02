import { connect } from '@permaweb/aoconnect';
import { pLimit } from 'plimit-lit';

const throttle = pLimit(5);

const arioProcessId =
  process.env.ARIO_NETWORK_PROCESS_ID ||
  'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE';

// TODO: add back in when we have a local ao-cu that can be used for testing this - as is we need results cached
const suRouter = process.env.SU_ROUTER || 'https://su-router.ao-testnet.xyz';
const ao = connect({
  CU_URL: process.env.CU_URL || 'http://cu.ardrive.io',
});

const graphqlUrl = process.env.GRAPHQL_URL || 'https://arweave.net/graphql';

// get all messages for a process by action from a given timestamp
async function getMessagesForProcessByAction({
  processId,
  fromTimestamp,
  toTimestamp,
  action,
}) {
  const res = await fetch(
    `${suRouter}/${processId}?from=${fromTimestamp.toString()}&to=${toTimestamp.toString()}&limit=10000`,
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

// returns a list of ids that are processes
async function getProcessMetadataFromGql({ processIds }) {
  let attempts = 0;
  const maxAttempts = 10;
  const backoffTime = 1000; // 1 second
  let cursor = null;
  const checkedProcessIds = [];
  let hasNextPage = true;

  while (attempts < maxAttempts && hasNextPage) {
    try {
      const res = await fetch(graphqlUrl, {
        method: 'POST',
        body: JSON.stringify({
          query: `query {
      transactions(
      first: 100
      ${cursor ? `after: "${cursor}"` : ''}
      ids: [${processIds.map((id) => `"${id}"`).join(',')} ]
      tags: [
        { name: "Data-Protocol", values: ["ao"] },
        { name: "Variant", values: ["ao.TN.1"] },
        { name: "Type", values: ["Process"] },
      ]
      ) {
      pageInfo {
          hasNextPage
      }
        edges {
        cursor
          node {
            id
            tags {
              name
              value
            }
          }
        }
      }
    }`,
        }),
      });
      const data = await res.json();
      checkedProcessIds.concat(
        data.data.transactions.edges.map((edge) => edge.node.id),
      );
      cursor = data.data.transactions.edges.at(-1)?.cursor ?? null;
      hasNextPage = Boolean(data.data.transactions.pageInfo.hasNextPage);
    } catch (error) {
      console.error(error);
      attempts++;
      if (attempts < maxAttempts) {
        console.log(`Attempt ${attempts} failed. Retrying...`);
        await new Promise((resolve) =>
          setTimeout(resolve, backoffTime * attempts),
        );
      } else {
        throw error;
      }
    }
  }

  return checkedProcessIds;
}

/**
 * Get all scheduled messages for a process
 * this is used to validate the cranking chain
 * @param {string} processId - The process ID to get scheduled messages for
 * @param {string} fromTimestamp - The timestamp to start from
 * @param {string} fromProcessId - The process ID of the sender
 * @param {string[]} references - The references to filter by
 * @returns {Promise<Record<string, {messageId: string, target: string, timestamp: number | undefined}>>} - A map of references to message IDs
 */
async function mapReferencesToMessages({
  fromProcessId,
  toProcessId,
  references,
}) {
  const res = await fetch(graphqlUrl, {
    method: 'POST',
    body: JSON.stringify({
      query: `
query GetMessagesByReference {
  transactions(
  first: 100
    tags: [
{ name: "Data-Protocol", values: ["ao"] }
{ name: "Variant", values: ["ao.TN.1"] }
{ name: "Type", values: ["Message"] }
{ name: "Reference", values: [${references.map((r) => `"${r}"`).join(',')} ] }
{ name: "From-Process", values: ["${fromProcessId}"] }
    ]
    recipients:["${toProcessId}"]
  ) {
    edges {
      node {
        id
        tags {
          name
          value
        }
        recipient
        anchor
      }
    }
  }
}`,
    }),
  });
  const data = await res.json();
  const edges = data.data.transactions.edges;
  // could have duplicate references
  const messagesToReferences = edges.reduce((acc, edge) => {
    const ref = edge.node.tags.find((t) => t.name === 'Reference')?.value;
    if (!ref) return acc;
    return {
      ...acc,
      [edge.node.id]: {
        target: edge.node.recipient,
        ref,
        node: edge.node,
      },
    };
  }, {});

  // set the timestamp for each message from its assignment
  await Promise.all(
    Object.entries(messagesToReferences).map(
      async ([messageId, { target }]) => {
        try {
          const res = await fetch(
            `${suRouter}/${messageId}?process-id=${target}`,
            {
              method: 'GET',
            },
          );
          const data = await res.json();
          const assignment = data.assignment;
          if (assignment) {
            messagesToReferences[messageId].timestamp = parseInt(
              assignment.tags.find((t) => t.name == 'Timestamp')?.value,
            );
          }
        } catch (error) {
          console.error(error);
        }
      },
    ),
  );

  // filter out duplicates and use the timestamp to sort
  const referencesToMessages = Object.entries(messagesToReferences).reduce(
    (acc, [messageId, { target, ref, timestamp }]) => {
      if (acc[ref]) {
        if (!acc[ref].timestamp || timestamp > acc[ref].timestamp) {
          return { ...acc, [ref]: { messageId, target, timestamp } };
        }
      }
      return { ...acc, [ref]: { messageId, target, timestamp } };
    },
    {},
  );

  return referencesToMessages;
}

/**
 * Validate the cranking chain for a given message
 * @param {string} originMessageId - The message ID to validate
 * @param {string} fromTimestamp - The timestamp to start from
 * @returns {Promise<Record<string, {messageId: string, target: string, timestamp: number | undefined} | null>>} - A map of references to message IDs
 */
async function validateCrankingChain({
  originMessageId,
  fromTimestamp,
  toTimestamp,
}) {
  const results = await ao.result({
    message: originMessageId,
    process: arioProcessId,
  });
  const messages = results.Messages;
  const processIds = await getProcessMetadataFromGql({
    processIds: messages.map((m) => m.Target),
  });

  const targetsToReferences = messages.reduce((acc, m) => {
    const ref = m.Tags.find(
      (t) => t.name === '_Ref' || t.name === 'Reference',
    )?.value;
    // only check messages that were sent to a process
    if (!ref || !processIds.includes(m.Target)) return acc;
    return { ...acc, [m.Target]: [...(acc[m.Target] ?? []), ref] };
  }, {});

  const allReferences = Object.values(targetsToReferences).flat();
  const referencesToMessages = allReferences.reduce((acc, ref) => {
    acc[ref] = null;
    return acc;
  }, {});

  await Promise.all(
    Object.entries(targetsToReferences).map(async ([processId, references]) => {
      const res = await mapReferencesToMessages({
        toProcessId: processId,
        fromTimestamp,
        toTimestamp,
        fromProcessId: arioProcessId,
        references,
      }).catch((e) => {
        // if the process is not found, we can ignore it as its likely a user not a process
        return;
      });

      if (!res) return;
      Object.entries(res).forEach(([ref, message]) => {
        referencesToMessages[ref] = message;
      });
    }),
  );
  return referencesToMessages;
}

async function main() {
  // Get the last checked timestamp
  const currentTimestamp = Date.now();
  // 5 minute grace period for messages to be cranked
  const toTimestamp = (currentTimestamp - 1000 * 60 * 5).toString(); // up till 5 minutes ago
  const twoHoursMs = 2 * 60 * 60 * 1000;
  // check the last 2 hours worth of messages
  // TODO: save the last checked timestamp and persist across github actions jobs
  const fromTimestamp = (currentTimestamp - twoHoursMs).toString();

  // Your existing logic to fetch and check transfer messages
  const transferMessages = await getMessagesForProcessByAction({
    processId: arioProcessId,
    fromTimestamp,
    toTimestamp,
    action: 'Transfer',
  });

  const messageStatuses = transferMessages.reduce(async (acc, messageId) => {
    acc[messageId] = null;
    return acc;
  }, {});

  const failedCrankings = new Map();

  await Promise.all(
    transferMessages.map(async (originMessageId) =>
      throttle(async () => {
        // sets the references to messages for the origin message. No message means the message was not on gql, no timestamp means the reference was not on the SU
        messageStatuses[originMessageId] = await validateCrankingChain({
          originMessageId: originMessageId,
          fromTimestamp,
          toTimestamp,
        });
        Object.entries(messageStatuses[originMessageId]).forEach(
          ([ref, message]) => {
            if (!message || !message.timestamp) {
              // discoverable using From-Process and Reference tags (in this case arioProcessId and ref)
              failedCrankings.set(originMessageId, { ref, message });
            }
          },
        );
      }),
    ),
  );

  if (failedCrankings.size > 0) {
    throw new Error(
      `Failed Crankings: ${JSON.stringify(
        Array.from(failedCrankings).map(([originMessageId, message]) => ({
          originMessageId,
          message,
        })),
      )}`,
    );
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
