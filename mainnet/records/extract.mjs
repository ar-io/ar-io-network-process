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
    default: './outputs/arns_records.csv',
  })
  .help()
  .parseSync();

const processId = argv.processId;
const dryRun = argv.dryRun;
const output = path.join(__dirname, argv.output);

console.log(
  'Pulling records from process',
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

const { items: records } = await ario.getArNSRecords({
  limit: 5000,
});

const activeRecords = records.filter(
  (record) => record.type === 'permabuy' || record.endTimestamp > Date.now(),
);

// mkdir if not exists
fs.mkdirSync(path.dirname(output), { recursive: true });

// overwrite the file if it exists
fs.writeFileSync(output, '');

// write the header
fs.appendFileSync(
  output,
  'name,processId,type,startTimestamp,endTimestamp,purchasePrice\n',
);

for (const record of activeRecords) {
  const { name, processId, type, startTimestamp, endTimestamp, purchasePrice } =
    record;

  const csvRow = [
    name,
    processId,
    type,
    startTimestamp,
    endTimestamp,
    purchasePrice,
  ].join(',');
  if (dryRun) {
    console.log(csvRow);
  } else {
    fs.appendFileSync(output, `${csvRow}\n`);
  }
}

console.log('Done');
