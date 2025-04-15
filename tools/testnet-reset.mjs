import {
  AOProcess,
  createAoSigner,
  ArweaveSigner,
  ARIO_TESTNET_PROCESS_ID,
  ARIOToken,
} from '@ar.io/sdk/node';
import { connect } from '@permaweb/aoconnect';

const wallet = JSON.parse(process.env.WALLET);
const processId =
  process.env.ARIO_NETWORK_PROCESS_ID || ARIO_TESTNET_PROCESS_ID;
const signer = createAoSigner(new ArweaveSigner(wallet));
const networkProcess = new AOProcess({
  processId,
  ao: connect({
    CU_URL: process.env.AO_CU_URL,
  }),
});

const protocolBalance =
  process.env.ARIO_PROTOCOL_BALANCE ||
  new ARIOToken(65 * 10 ** 12).toAmount(65_000_000);
const teamWalletBalance =
  process.env.ARIO_TEAM_WALLET_BALANCE ||
  new ARIOToken(50 * 10 ** 12).toAmount(50_000_000);
const teamWalletAddress = (process.env.ARIO_TEAM_WALLET_ADDRESS || '')
  .trim()
  .split(',');
const ownerBalance = 10 ** 15 - protocolBalance - teamWalletBalance;
const { id } = await networkProcess.send({
  tags: [{ name: 'Action', value: 'Eval' }],
  data: ```
    PrimaryNames.owners={}
    PrimaryNames.names={}
    GatewayRegistry = {}
    NameRegistry.records={}
    NameRegistry.returned={}
    Epochs={}
    Balances={
        [Owner]=${ownerBalance},
        ${processId}=${protocolBalance},
        ${teamWalletAddress.map((address) => `${address}=${teamWalletBalance}`).join(',\n')}
    }
  ```,
  signer,
});
console.log(`Evolve result tx: ${id}`);
