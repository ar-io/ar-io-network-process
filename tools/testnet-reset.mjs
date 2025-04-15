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
    CU_URL: process.env.AO_CU_URL || 'https://cu.ardrive.io',
  }),
});

const protocolBalance =
  process.env.ARIO_PROTOCOL_BALANCE ||
  new ARIOToken(65 * 10 ** 12).toMARIO().value;
const teamWalletBalance =
  process.env.ARIO_TEAM_WALLET_BALANCE ||
  new ARIOToken(50 * 10 ** 12).toMARIO().value;
const teamWalletAddress = (
  process.env.ARIO_TEAM_WALLET_ADDRESS ||
  'OZJjbPv98Qp8pJTZbKCmwlmhutGCW_zZ-18MjdBZQRY,DyQ3ZT4LSxSqx9CqFBb7O_28vE3bc7HsVA6jDvufpwc'
)
  .trim()
  .split(',');
const ownerBalance = 10 ** 15 - protocolBalance - teamWalletBalance;
const { id } = await networkProcess.send({
  tags: [{ name: 'Action', value: 'Eval' }],
  data: ```
    PrimaryNames.owners={}
    PrimaryNames.names={}
    GatewayRegistry={}
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
console.log(`Testnet reset tx: ${id}`);
