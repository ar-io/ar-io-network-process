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
    default: './outputs/balances.lua',
  })
  .option('input', {
    alias: 'i',
    type: 'string',
    description: 'Input CSV file path',
    default: './outputs/balances.csv',
  })
  .help()
  .parseSync();

const dryRun = argv.dryRun;
const output = argv.output;
const input = argv.input;
console.log('Creating raw balances from', input, 'and writing to', output);

// overwrite the file if it exists
fs.writeFileSync(path.join(process.cwd(), output), '');

// read all the records from the input file
const balances = fs
  .readFileSync(path.join(process.cwd(), input), 'utf8')
  .split('\n')
  .slice(1)
  .map((row) => row.trim())
  .filter((row) => row.length > 0)
  .filter(Boolean) // Remove empty lines
  .map((row) => row.split(','));

for (const balance of balances) {
  const [address, mARIOQty] = balance;
  const luaRecord = `Balances["${address}"] = ${mARIOQty};\n`;
  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

console.log('Done');
