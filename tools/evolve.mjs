import { AOProcess, createAoSigner } from '@ar.io/sdk';
import { BUNDLED_AOS_LUA } from './constants.js';

const registryId = process.env.REGISTRY_ID;
const wallet = JSON.parse(process.env.WALLET);
const process = new AOProcess({ processId: registryId });

const signer = createAoSigner(new ArweaveSigner(wallet));

const evolveResult = await process.send({
  tags: [{ name: 'Action', value: 'Eval' }],
  data: BUNDLED_AOS_LUA,
  signer,
});
console.log(`Evolve result: ${evolveResult}`);
