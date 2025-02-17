import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

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
const output = path.join(__dirname, argv.output);
const input = path.join(__dirname, argv.input);

console.log('Creating raw lua records from', input, 'and writing to', output);

// mkdir if not exists
fs.mkdirSync(path.dirname(output), { recursive: true });

// overwrite the file if it exists
fs.writeFileSync(output, '');

// read all the records from the input file
const records = fs
  .readFileSync(input, 'utf8')
  .split('\n')
  .slice(1)
  .filter(Boolean)
  .map((line) => line.split(','));

for (const record of records) {
  const [
    name,
    processId,
    type,
    startTimestamp,
    endTimestamp,
    purchasePrice,
    undernameLimit,
  ] = record;
  // // append to lua file
  const luaRecord = `
NameRegistry.records["${name}"] = {
    processId = "${processId}",
    type = "${type}",
    startTimestamp = ${startTimestamp},
    endTimestamp = ${endTimestamp || 'nil'},
    purchasePrice = ${purchasePrice},
    undernameLimit = ${undernameLimit}
  }\n`;

  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

console.log('Done');
