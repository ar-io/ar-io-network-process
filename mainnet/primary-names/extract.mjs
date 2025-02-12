import { AOProcess, ARIO, ARIO_TESTNET_PROCESS_ID } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import fs from 'fs';
import path from 'path';

const argv = yargs(hideBin(process.argv))
  .option('processId', {
    alias: 'p',
    type: 'string',
    description: 'Process ID for the gateway registration',
    default: ARIO_TESTNET_PROCESS_ID,
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
    default: './outputs/primary_names.csv',
  })
  .help()
  .parseSync();

const processId = argv.processId;
const dryRun = argv.dryRun;
const output = argv.output;

console.log(
  'Pulling primary names from process',
  processId,
  'and writing to',
  output,
);

const ario = ARIO.init({
  process: new AOProcess({
    processId,
    ao: connect({
      CU_URL: 'https://cu.ardrive.io',
    }),
  }),
});

const { items: primaryNames } = await ario.getPrimaryNames({
  limit: 5000,
});

// overwrite the file if it exists
fs.writeFileSync(path.join(process.cwd(), output), '');

// write the header
fs.appendFileSync(output, 'name,address,processId\n');

for (const primaryName of primaryNames) {
  const { name, owner: address, processId } = primaryName;

  const csvRow = [name, address, processId].join(',');
  if (dryRun) {
    console.log(csvRow);
  } else {
    fs.appendFileSync(output, `${csvRow}\n`);
  }
}

console.log('Done');
