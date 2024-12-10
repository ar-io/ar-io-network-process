import { IO_DEVNET_PROCESS_ID, IO_TESTNET_PROCESS_ID } from '@ar.io/sdk';
import fs from 'node:fs';
import path from 'node:path';
import { pipeline } from 'node:stream';
import { promisify } from 'node:util';

const __dirname = new URL('.', import.meta.url).pathname;
async function main() {
  try {
    const network = process.env.IO_NETWORK ?? 'testnet';
    console.log(`=== Retrieving ${network} process memory === \n\n`);
    const ioProcessId =
      process.env.IO_NETWORK === 'devnet'
        ? IO_DEVNET_PROCESS_ID
        : IO_TESTNET_PROCESS_ID;

    const fetchStream = await fetch(
      `https://cu.ardrive.io/state/${ioProcessId}`,
    );
    const memPath = path.join(__dirname, 'fixtures', 'memory', `${network}`);
    const writeStream = fs.createWriteStream(memPath, { recursive: true });
    await promisify(pipeline)(fetchStream.body, writeStream);
    console.log(`Wrote memory to ${memPath} \n\n`);
  } catch (error) {
    console.error(error);
  }
}

main();
