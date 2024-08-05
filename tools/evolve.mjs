import { AOProcess, createAoSigner } from '@ar.io/sdk/node';
import constants from './constants.js';

const registryId = process.env.REGISTRY_ID;
const wallet = JSON.parse(process.env.WALLET);
const signer = createAoSigner(new ArweaveSigner(wallet));
const networkProcess = new AOProcess({ processId: registryId });

const evolveResult = await networkProcess.send({
  tags: [{ name: 'Action', value: 'Eval' }],
  data: constants.BUNDLED_AOS_LUA,
  signer,
});
console.log(`Evolve result: ${evolveResult}`);
