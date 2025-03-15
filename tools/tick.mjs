import {
  AOProcess,
  createAoSigner,
  ArweaveSigner,
  ARIO_MAINNET_PROCESS_ID,
} from '@ar.io/sdk/node';
import { connect } from '@permaweb/aoconnect';

const WALLET = process.env.WALLET;
const ARIO_NETWORK_PROCESS_ID =
  process.env.ARIO_NETWORK_PROCESS_ID || ARIO_MAINNET_PROCESS_ID;
const AO_CU_URL = process.env.AO_CU_URL || 'https://cu.ardrive.io';

if (!WALLET) {
  throw new Error('WALLET is not set');
}

const wallet = JSON.parse(WALLET);
const signer = createAoSigner(new ArweaveSigner(wallet));
const networkProcess = new AOProcess({
  processId: ARIO_NETWORK_PROCESS_ID,
  ao: connect({
    CU_URL: AO_CU_URL,
  }),
});

const { id, result } = await networkProcess.send({
  tags: [{ name: 'Action', value: 'Tick' }],
  signer,
});
console.log(`Tick result tx: ${id}\n${JSON.stringify(result, null, 2)}`);
