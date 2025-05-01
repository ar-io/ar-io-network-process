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

// 1B tARIO total supply
const totalSupply = new ARIOToken(10 ** 9).toMARIO().valueOf();
// 65M tARIO to the protocol
const protocolBalance = new ARIOToken(65 * 10 ** 6).toMARIO().valueOf();
// 50M tARIO to each of the team wallets
const teamWalletBalance = new ARIOToken(50 * 10 ** 6).toMARIO().valueOf();
// any team wallets needed for testing
const teamWalletAddresses = (
  process.env.ARIO_TEAM_WALLET_ADDRESSES ||
  'OZJjbPv98Qp8pJTZbKCmwlmhutGCW_zZ-18MjdBZQRY,DyQ3ZT4LSxSqx9CqFBb7O_28vE3bc7HsVA6jDvufpwc'
)
  .trim()
  .split(',');
// the owner balance is the total supply minus the protocol balance and the team wallet balance
const ownerBalance =
  totalSupply -
  protocolBalance -
  teamWalletBalance * teamWalletAddresses.length;
const { id } = await networkProcess.send({
  tags: [{ name: 'Action', value: 'Eval' }],
  data: `
    PrimaryNames.owners={}
    PrimaryNames.names={}
    GatewayRegistry={}
    DemandFactor.currentDemandFactor=1
    NameRegistry.records={
      ardrive={
        processId = "FAoLsl-FuRYap2WCTLE1xkMzoK3fuu2Pq-E5-F9Cy-A",
        purchasePrice = 0,
        type = "permabuy",
        startTimestamp = 1741799881987,
        undernameLimit = 10
      },
      ["undername-limits"]={
        processId = "YvtwbdthqwEjAvuPMckzBSWyeGFlcLoJzpbLdyFNY-w",
        purchasePrice = 0,
        type = "permabuy",
        startTimestamp = 1741799881987,
        undernameLimit = 10
      }
    }
    NameRegistry.returned={}
    Balances={
      [Owner]=${ownerBalance},
      ${processId}=${protocolBalance},
      ${teamWalletAddress.map((address) => `["${address}"]=${teamWalletBalance}`).join(',\n')}
    }
  `,
  signer,
});
console.log(`Testnet reset tx: ${id}`);
