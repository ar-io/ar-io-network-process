import { AOProcess, ARIO, ARIO_TESTNET_PROCESS_ID } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
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
  .option('output-balances', {
    alias: 'o',
    type: 'string',
    description: 'Output CSV file path',
    default: './outputs/liquid_balances.csv',
  })
  .option('output-delegates', {
    alias: 'l',
    type: 'string',
    description: 'Output CSV file path for assigned delegates',
    default: './outputs/assigned_delegates.csv',
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
const outputBalances = argv['output-balances'];
const outputDelegates = argv['output-delegates'];
const gatewaysFile = argv['gateways-file'];
const stakedMultiplier = argv['staked-multiplier'];
console.log(
  'Pulling liquid balances from AIRDROP process',
  processId,
  'and writing to',
  outputBalances,
  'and delegates to',
  outputDelegates,
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

// overwrite the file if it exists
fs.writeFileSync(path.join(process.cwd(), outputBalances), '');

// write the header
fs.appendFileSync(outputBalances, 'address,mARIOQty\n');

const liquidRegistrants = registrants.filter((r) => r.type === 'wallet');

// assign the liquid balances
for (const registrant of liquidRegistrants) {
  const { address, mARIOBaseQty } = registrant;

  const csvRow = [address, mARIOBaseQty].join(',');
  if (dryRun) {
    console.log(csvRow);
  } else {
    fs.appendFileSync(outputBalances, `${csvRow}\n`);
  }
}

// assign the delegates
fs.writeFileSync(path.join(process.cwd(), outputDelegates), '');

// write the header
fs.appendFileSync(
  outputDelegates,
  'gatewayAddress,delegateAddress,delegateStake\n',
);

const gatewayAddresses = fs
  .readFileSync(gatewaysFile, 'utf8')
  .split('\n')
  .slice(1) // Skip header row
  .filter(Boolean) // Remove empty lines
  .map((line) => line.split(',')[1]); // Get just the address column
const stakedRegistrants = registrants.filter((r) => r.type === 'stake');

console.log(
  `Assigning ${stakedRegistrants.length} staked registrations to ${gatewayAddresses.length} gateways`,
);

for (const registrant of stakedRegistrants) {
  const { address: delegateAddress, mARIOBaseQty } = registrant;

  // compute the assigned gateway based on the hash of the address
  const delegateHash = crypto
    .createHash('sha256')
    .update(delegateAddress)
    .digest('hex');
  const truncatedHash = delegateHash.substring(0, 8);
  const gatewayAddress =
    gatewayAddresses[parseInt(truncatedHash, 16) % gatewayAddresses.length];

  // assign the delegate
  const delegateStake = mARIOBaseQty * stakedMultiplier;
  const csvRow = [gatewayAddress, delegateAddress, delegateStake].join(',');
  if (dryRun) {
    console.log(csvRow);
  } else {
    fs.appendFileSync(outputDelegates, `${csvRow}\n`);
  }
}

console.log('Done');
