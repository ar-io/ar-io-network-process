import { AOProcess, ARIO, ARIO_TESTNET_PROCESS_ID } from '@ar.io/sdk';
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
    default: './outputs/gateways.csv',
  })
  .help()
  .parseSync();

const processId = argv.processId;
const dryRun = argv.dryRun;
const output = path.join(__dirname, argv.output);

console.log('Pulling gateways from process', processId);

// extracts gateways from the ARIO testnet process and produces a CSV with defaulted values

const ario = ARIO.init({
  process: new AOProcess({
    processId,
    ao: connect({
      CU_URL: 'https://cu.ardrive.io',
    }),
  }),
});

const { items: gateways } = await ario.getGateways({
  limit: 1000,
});

const nonLeavingGateways = gateways.filter(
  (gateway) => gateway.status !== 'leaving',
);

// mkdir if not exists
fs.mkdirSync(path.dirname(output), { recursive: true });

// overwrite the file if it exists
fs.writeFileSync(output, '');

// write the header
fs.appendFileSync(
  output,
  'gatewayAddress,observerAddress,operatorStake,fqdn,port,protocol,allowDelegatedStaking,delegateRewardShareRatio,allowedDelegates,minDelegatedStake,autoStake,label,note,properties,status,failedConsecutiveEpochsCount\n',
);

for (const gateway of nonLeavingGateways) {
  const {
    gatewayAddress,
    observerAddress,
    settings,
    status,
    stats,
    operatorStake,
  } = gateway;

  const csvRow = [
    gatewayAddress,
    observerAddress,
    operatorStake,
    settings.fqdn,
    settings.port,
    settings.protocol,
    settings.allowDelegatedStaking,
    settings.delegateRewardShareRatio,
    settings.allowedDelegates,
    settings.minDelegatedStake,
    settings.autoStake,
    settings.label,
    settings.note,
    settings.properties,
    status,
    stats.failedConsecutiveEpochsCount,
  ].join(',');
  if (dryRun) {
    console.log(csvRow);
  } else {
    fs.appendFileSync(output, `${csvRow}\n`);
  }
}

console.log('Done');
