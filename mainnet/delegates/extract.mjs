import { AOProcess } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';

import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const argv = yargs(hideBin(process.argv))
  .option('processId', {
    alias: 'p',
    type: 'string',
    description: 'Process ID for the gateway registration',
    default: '8Y3BJ6YHtp0uiaM0KSyCdTqLYVJvGLZZI5QjPPskL7I', // the airdrop process ID
  })
  .option('dryRun', {
    alias: 'd',
    type: 'boolean',
    description: 'Run without making any changes',
    default: false,
  })
  .option('output', {
    alias: 'o',
    type: 'string',
    description: 'Output CSV file path',
    default: './outputs/delegates.csv',
  })
  .option('gateways-file', {
    alias: 'g',
    type: 'string',
    description: 'Gateways CSV file path',
    default: '../gateways/outputs/gateways.csv',
  })
  .option('staked-multiplier', {
    alias: 'm',
    type: 'number',
    description: 'The multiplier for staked wallets',
    default: 1.25, // 25% for staked wallets
  })
  .help()
  .parseSync();

const processId = argv.processId;
const dryRun = argv.dryRun;
const output = path.join(__dirname, argv.output);
const gatewaysFile = path.join(__dirname, argv['gateways-file']);
const stakedMultiplier = argv['staked-multiplier'];

console.log(
  'Pulling delegates from AIRDROP process',
  processId,
  'and writing to',
  output,
);

const airdrop = new AOProcess({
  processId,
  ao: connect({
    CU_URL: 'https://cu.ardrive.io',
  }),
});

const { items: registrants } = await airdrop.read({
  tags: [
    {
      name: 'Action',
      value: 'Get-Registrations',
    },
    {
      name: 'Page-Size',
      value: '15000',
    },
  ],
});

// mkdir if not exists
fs.mkdirSync(path.dirname(output), { recursive: true });

// overwrite the file if it exists
fs.writeFileSync(output, '');

// write the header
fs.appendFileSync(output, 'delegateAddress,gatewayAddress,delegateStake\n');

const gatewayAddresses = fs
  .readFileSync(gatewaysFile, 'utf8')
  .split('\n')
  .slice(1) // Skip header row
  .filter(Boolean) // Remove empty lines
  .map((line) => line.split(',')[0]); // Get just the address column
const stakedRegistrants = registrants.filter((r) => r.type === 'stake');

console.log(
  `Assigning ${stakedRegistrants.length} staked registrations to ${gatewayAddresses.length} gateways`,
);

for (const registrant of stakedRegistrants) {
  const { address: delegateAddress, mARIOBaseQty } = registrant;

  // compute the assigned gateway based on the hash of the address
  // TODO: check with GPT that this is normally distributed
  const delegateHash = crypto
    .createHash('sha256')
    .update(delegateAddress)
    .digest('hex');
  const truncatedHash = delegateHash.substring(0, 32);
  const gatewayAddress =
    gatewayAddresses[parseInt(truncatedHash, 16) % gatewayAddresses.length];

  // assign the delegate
  const delegateStake = mARIOBaseQty * stakedMultiplier;
  const csvRow = [delegateAddress, gatewayAddress, delegateStake].join(',');
  if (dryRun) {
    console.log(csvRow);
  } else {
    fs.appendFileSync(output, `${csvRow}\n`);
  }
}

console.log('Done');
