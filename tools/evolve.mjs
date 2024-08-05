import { AOProcess, createAoSigner, ArweaveSigner } from '@ar.io/sdk/node';
import constants from './constants.js';

const processId = process.env.IO_NETWORK_PROCESS_ID;
const wallet = JSON.parse(process.env.WALLET);
const signer = createAoSigner(new ArweaveSigner(wallet));
const networkProcess = new AOProcess({ processId });

const { id } = await networkProcess.send({
  tags: [{ name: 'Action', value: 'Eval' }],
  data: constants.BUNDLED_SOURCE_CODE,
  signer,
});
console.log(`Evolve result tx: ${id}`);
