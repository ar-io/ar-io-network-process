import { AOProcess } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import fs from 'fs';
import path from 'path';
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
    default: './outputs/balances.csv',
  })
  .help()
  .parseSync();

const processId = argv.processId;
const dryRun = argv.dryRun;
const output = path.join(__dirname, argv.output);

console.log(
  'Pulling liquid balances from AIRDROP process',
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
fs.appendFileSync(output, 'address,mARIOQty\n');

const liquidRegistrants = registrants.filter((r) => r.type === 'wallet');

// assign the liquid balances
for (const registrant of liquidRegistrants) {
  const { address, mARIOBaseQty } = registrant;

  const csvRow = [address, mARIOBaseQty].join(',');
  if (dryRun) {
    console.log(csvRow);
  } else {
    fs.appendFileSync(output, `${csvRow}\n`);
  }
}

console.log('Done');
