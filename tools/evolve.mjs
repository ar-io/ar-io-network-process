import { AOProcess, createAoSigner, ArweaveSigner } from '@ar.io/sdk/node';
import * as constants from './constants.mjs';
import { connect } from '@permaweb/aoconnect';
import { execSync } from 'child_process';

// Retrieve the Git hash directly in the script
let gitHash;
try {
  gitHash = execSync('git rev-parse --short HEAD').toString().trim();
} catch (error) {
  console.error('Error retrieving Git hash:', error);
  gitHash = 'unknown';
}

const wallet = JSON.parse(process.env.WALLET);
const signer = createAoSigner(new ArweaveSigner(wallet));
const networkProcess = new AOProcess({
  processId: process.env.IO_NETWORK_PROCESS_ID,
  ao: connect({
    CU_URL: process.env.AO_CU_URL,
  }),
});

const { id } = await networkProcess.send({
  tags: [
    { name: 'Action', value: 'Eval' },
    { name: 'Git-Hash', value: gitHash },
  ],
  data: constants.BUNDLED_SOURCE_CODE,
  signer,
});
console.log(`Evolve result tx: ${id}`);
