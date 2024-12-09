import { AOProcess, createAoSigner, ArweaveSigner } from '@ar.io/sdk/node';
import * as constants from './constants.mjs';
import { connect } from '@permaweb/aoconnect';
import { execSync } from 'child_process';

const wallet = JSON.parse(process.env.WALLET);
const signer = createAoSigner(new ArweaveSigner(wallet));
const networkProcess = new AOProcess({
  processId: process.env.IO_NETWORK_PROCESS_ID, // TODO: Update to ARIO_NETWORK_PROCESS_ID
  ao: connect({
    CU_URL: process.env.AO_CU_URL,
  }),
});

const tags = [{ name: 'Action', value: 'Eval' }];

try {
  // Gracefully retrieve the Git hash directly in the script
  const gitHash = execSync('git rev-parse --short HEAD').toString().trim();
  tags.push({ name: 'Git-Hash', value: gitHash });
} catch (error) {
  console.error('Error retrieving Git hash:', error);
}

const { id } = await networkProcess.send({
  tags,
  data: constants.BUNDLED_SOURCE_CODE,
  signer,
});
console.log(`Evolve result tx: ${id}`);
