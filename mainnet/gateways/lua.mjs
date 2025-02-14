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
    default: './outputs/gateways.lua',
  })
  .option('input', {
    alias: 'i',
    type: 'string',
    description: 'Input CSV file path',
    default: './outputs/gateways.csv',
  })
  .help()
  .parseSync();

const dryRun = argv.dryRun;
const output = path.join(__dirname, argv.output);
const input = path.join(__dirname, argv.input);

console.log(
  'Creating raw lua gateways with assigned delegates from',
  input,
  'and writing to',
  output,
);

// mkdir if not exists
fs.mkdirSync(path.dirname(output), { recursive: true });

// overwrite the file if it exists
fs.writeFileSync(output, '');

// read all the records from the input file
// gatewayAddress,observerAddress,operatorStake,fqdn,port,protocol,allowDelegatedStaking,delegateRewardShareRatio,minDelegatedStake,autoStake,label,note,properties,status,failedConsecutiveEpochsCount
const gateways = fs
  .readFileSync(input, 'utf8')
  .split('\n')
  .slice(1)
  .map((row) => row.trim())
  .filter((row) => row.length > 0)
  .filter(Boolean) // Remove empty lines
  .map((row) => row.split(','));

for (const gateway of gateways) {
  const [
    gatewayAddress,
    observerAddress,
    operatorStake,
    fqdn,
    port,
    protocol,
    allowDelegatedStaking,
    delegateRewardShareRatio,
    minDelegatedStake,
    autoStake,
    label,
    note,
    properties,
    status,
    failedConsecutiveEpochsCount,
  ] = gateway;
  const luaRecord = `
GatewayRegistry["${gatewayAddress}"] = {
    observerAddress = "${observerAddress}",
    operatorStake = ${operatorStake},
    totalDelegatedStake = 0,
    settings = {
        fqdn = "${fqdn}",
        port = ${port},
        note = "${note}",
        label = "${label}",
        protocol = "${protocol}",
        properties = "${properties}",
        minDelegatedStake = ${minDelegatedStake},
        allowDelegatedStaking = ${allowDelegatedStaking},
        delegateRewardShareRatio = ${delegateRewardShareRatio},
        autoStake = ${autoStake},
        allowedDelegates = {},
    },
    delegates = {},
    vaults = {},
    services = {},
    status = "joined",
    weights = {
        compositeWeight = 0,
        normalizedCompositeWeight = 0,
        stakeWeight = 0,
        tenureWeight = 0,
        gatewayPerformanceRatio = 0,
        observerPerformanceRatio = 0,
    },
    stats = {
        prescribedEpochCount = 0,
        observedEpochCount = 0,
        totalEpochCount = 0,
        passedEpochCount = 0,
        failedEpochCount = 0,
        failedConsecutiveEpochs = 0,
        passedConsecutiveEpochs = 0,
    }
}
  `;
  if (dryRun) {
    console.log(luaRecord);
  } else {
    fs.appendFileSync(output, luaRecord);
  }
}

console.log('Done');
