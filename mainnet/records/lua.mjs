import { AOProcess, ARIO, ARIO_TESTNET_PROCESS_ID } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import fs from 'fs';
import path from 'path';

const argv = yargs(hideBin(process.argv))
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
    default: './outputs/arns_records.lua',
  })
  .option('input', {
    alias: 'i',
    type: 'string',
    description: 'Input CSV file path',
    default: './outputs/arns_records.csv',
  })
  .help()
  .parseSync();

const dryRun = argv.dryRun;
const output = argv.output;
const input = argv.input;

console.log('Creating raw lua records from', input, 'and writing to', output);

// overwrite the file if it exists
fs.writeFileSync(path.join(process.cwd(), output), '');

// read all the records from the input file
const records = fs.readFileSync(path.join(process.cwd(), input), 'utf8').split('\n').slice(1);

for (const record of records) {
  const [name, processId, type, startTimestamp, endTimestamp, purchasePrice] =
    record.split(',');
  // // append to lua file
  const luaRecord = `NameRegistry.records["${name}"] = {
      processId = "${processId}",
      type = "${type}",
      startTimestamp = ${startTimestamp},
      endTimestamp = ${endTimestamp || 'nil'},
      purchasePrice = ${purchasePrice}
    }\n`;

  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

console.log('Done');
