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
    default: './outputs/gateways.lua',
  })
  .option('input', {
    alias: 'i',
    type: 'string',
    description: 'Input CSV file path',
    default: './outputs/gateways.csv',
  })
  .option('start-timestamp', {
    alias: 's',
    type: 'number',
    description: 'Start timestamp for the gateway and all delegates',
    default: Date.now(),
  })
  .option('assigned-delegates-input', {
    alias: 'a',
    type: 'string',
    description: 'Input CSV file path for assigned delegates',
    default: '../balances/outputs/assigned_delegates.csv',
  })
  .help()
  .parseSync();

const dryRun = argv.dryRun;
const output = argv.output;
const input = argv.input;
const startTimestamp = argv['start-timestamp'];
const assignedDelegatesInput = argv['assigned-delegates-input'];
console.log(
  'Creating raw lua gateways with assigned delegates from',
  input,
  'and writing to',
  output,
);

// overwrite the file if it exists
fs.writeFileSync(path.join(process.cwd(), output), '');

// read all the records from the input file
// gatewayAddress,observerAddress,operatorStake,fqdn,port,protocol,allowDelegatedStaking,delegateRewardShareRatio,allowedDelegates,minDelegatedStake,autoStake,label,note,properties,status,failedConsecutiveEpochsCount
const gateways = fs
  .readFileSync(path.join(process.cwd(), input), 'utf8')
  .split('\n')
  .slice(1)
  .map(row => row.trim())
  .filter(row => row.length > 0)
  .filter(Boolean) // Remove empty lines
  .map(row => row.split(','));

const assignedDelegates = fs
  .readFileSync(path.join(process.cwd(), assignedDelegatesInput), 'utf8')
  .split('\n')
  .slice(1)
  .map(row => row.trim())
  .filter(row => row.length > 0)
  .filter(Boolean) // Remove empty lines
  .map(row => row.split(','));

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
    allowedDelegates,
    minDelegatedStake,
    autoStake,
    label,
    note,
    properties,
    status,
    failedConsecutiveEpochsCount,
  ] = gateway;
  // get all the delegates for the gateway from the input file
  let totalDelegatedStake = 0;
  let assignedDelegatesForGatewayLua = 'delegates = {\n';
  for (const delegate of assignedDelegates) {
    const [assignedGatewayAddress, delegateAddress, delegatedStake] = delegate;
    if (assignedGatewayAddress === gatewayAddress) {
      totalDelegatedStake += parseInt(delegatedStake);
      assignedDelegatesForGatewayLua += `\t\t\t["${delegateAddress}"] = { delegatedStake = ${delegatedStake}, startTimestamp = ${startTimestamp}, vaults = {} },\n`;
    }
  }
  assignedDelegatesForGatewayLua += '\t\t}';

  // consider separting delgates to separate file

  const luaRecord = `
GatewayRegistry["${gatewayAddress}"] = {
    observerAddress = "${observerAddress}",
    operatorStake = ${operatorStake},
    totalDelegatedStake = ${totalDelegatedStake},
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
    ${assignedDelegatesForGatewayLua},
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
        failedConsecutiveEpochsCount = 0,
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
