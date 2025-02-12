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
    default: './outputs/primary_names.lua',
  })
  .option('input', {
    alias: 'i',
    type: 'string',
    description: 'Input CSV file path',
    default: './outputs/primary_names.csv',
  })
  .option('start-timestamp', {
    alias: 's',
    type: 'number',
    description: 'Start timestamp',
    default: Date.now(),
  })
  .help()
  .parseSync();

const dryRun = argv.dryRun;
const output = argv.output;
const input = argv.input;
const startTimestamp = argv['start-timestamp'];
console.log('Creating raw lua records from', input, 'and writing to', output);

// overwrite the file if it exists
fs.writeFileSync(path.join(process.cwd(), output), '');

// read all the records from the input file
const primaryNames = fs
  .readFileSync(path.join(process.cwd(), input), 'utf8')
  .split('\n')
  .slice(1);

for (const primaryName of primaryNames) {
  const [name, address] = primaryName.split(',');
  // add both the owner and the name to the lua file
  const luaRecord = `PrimaryNames.owners["${address}"] = { name = "${name}", startTimestamp = ${startTimestamp} }\nPrimaryNames.names["${name}"] = "${address}"\n`;

  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

console.log('Done');
