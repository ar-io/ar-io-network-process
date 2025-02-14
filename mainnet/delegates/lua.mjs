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
    description: 'Start timestamp',
    default: Date.now(),
  })
  .help()
  .parseSync();

const dryRun = argv.dryRun;
const output = path.join(__dirname, argv.output);
const input = path.join(__dirname, argv.input);
const startTimestamp = argv['start-timestamp'];

console.log('Creating delegate balances from', input, 'and writing to', output);

// mkdir if not exists
fs.mkdirSync(path.dirname(output), { recursive: true });

// overwrite the file if it exists
fs.writeFileSync(output, '');

const gatewayDelegatedStakeTotals = {};
// now do the same with assigned delegates
const assignedDelegates = fs
  .readFileSync(input, 'utf8')
  .split('\n')
  .slice(1)
  .map((row) => row.trim())
  .filter((row) => row.length > 0)
  .filter(Boolean) // Remove empty lines
  .map((row) => row.split(','));

for (const delegate of assignedDelegates) {
  const [
    delegateAddress, 
    gatewayAddress,
    delegateStake,
    providedStartTimestamp,
  ] = delegate;
  if (!gatewayDelegatedStakeTotals[gatewayAddress]) {
    gatewayDelegatedStakeTotals[gatewayAddress] = 0;
  }
  gatewayDelegatedStakeTotals[gatewayAddress] += parseInt(delegateStake);
  const luaRecord = `GatewayRegistry["${gatewayAddress}"].delegates["${delegateAddress}"] = { delegatedStake = ${delegateStake}, startTimestamp = ${providedStartTimestamp || startTimestamp}, vaults = {} }\n`;
  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

for (const [gatewayAddress, totalDelegatedStake] of Object.entries(
  gatewayDelegatedStakeTotals,
)) {
  const luaRecord = `GatewayRegistry["${gatewayAddress}"].totalDelegatedStake = ${totalDelegatedStake};\n`;
  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

console.log('Done');
