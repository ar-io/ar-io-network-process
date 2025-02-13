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
    default: './outputs/delegates.lua',
  })
  .option('input', {
    alias: 'i',
    type: 'string',
    description: 'Input CSV file path',
    default: './outputs/delegates.csv',
  })
  .option('start-timestamp', {
    alias: 's',
    type: 'number',
    description: 'Start timestamp for the gateway and all delegates',
    default: Date.now(),
  })
  .help()
  .parseSync();

const dryRun = argv.dryRun;
const output = argv.output;
const input = argv.input;
const startTimestamp = argv.startTimestamp;

console.log('Creating delegate balances from', input, 'and writing to', output);

// overwrite the file if it exists
fs.writeFileSync(path.join(process.cwd(), output), '');

const gatewayDelegatedStakeTotals = {};
// now do the same with assigned delegates
const assignedDelegates = fs
  .readFileSync(path.join(process.cwd(), input), 'utf8')
  .split('\n')
  .slice(1)
  .map((row) => row.trim())
  .filter((row) => row.length > 0)
  .filter(Boolean) // Remove empty lines
  .map((row) => row.split(','));

for (const delegate of assignedDelegates) {
  const [address, delegateAddress, delegateStake] = delegate;
  if (!gatewayDelegatedStakeTotals[address]) {
    gatewayDelegatedStakeTotals[address] = 0;
  }
  gatewayDelegatedStakeTotals[address] += parseInt(delegateStake);
  const luaRecord = `GatewayRegistry["${address}"].delegates["${delegateAddress}"] = { delegatedStake = ${delegateStake}, startTimestamp = ${startTimestamp}, vaults = {} },\n`;
  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

for (const [address, totalDelegatedStake] of Object.entries(
  gatewayDelegatedStakeTotals,
)) {
  const luaRecord = `GatewayRegistry["${address}"].totalDelegatedStake = ${totalDelegatedStake};\n`;
  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

console.log('Done');
