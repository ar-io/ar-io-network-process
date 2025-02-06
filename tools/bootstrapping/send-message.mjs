import { message, createDataItemSigner } from '@permaweb/aoconnect';
import fs from 'fs';

const processId = 'KLSXAJmRRwliR7z3O39dob7o1jq556ETYYzl2xHvkjw';
const balancesJson = fs.readFileSync('./bootstrap-balances.json', 'utf8');
const jwk = JSON.parse(fs.readFileSync('./wallet.json', 'utf8'));

async function sendMessage() {
  console.log(`Sending message to ${processId}...`);

  const response = await message({
    process: processId,
    tags: [
      {
        name: 'Action',
        value: 'Load-Balances',
      },
    ],
    data: balancesJson,
    signer: createDataItemSigner(jwk),
  });
  console.log(`Response: ${JSON.stringify(response)}`);
}

await sendMessage();
