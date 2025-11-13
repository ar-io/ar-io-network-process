import fs from 'fs';
import path from 'path';
import { connect, createDataItemSigner } from '@permaweb/aoconnect';

const __dirname = path.dirname(new URL(import.meta.url).pathname);

// This is the _actual_ module id, but its a 16gb memory and not supported on legacynet
const moduleId = 'CWxzoe4IoNpFHiykadZWphZtLWybDF8ocNi7gmK6zCg';
// this is a module id that is supported on legacy net from around the same time.
//const moduleId = 'cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk';
const jwk = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'test-wallet.json'), 'utf8'),
);
const authority = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY';
const scheduler = '_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA';
const signer = createDataItemSigner(jwk);
const ao = connect({
  CU_URL: 'https://cu.ardrive.io',
});

const arioLua = fs.readFileSync(
  path.join(__dirname, '../dist/aos-bundled.lua'),
  'utf8',
);
const balancesLua = fs.readFileSync(
  path.join(__dirname, 'balances.lua'),
  'utf8',
);
const processLua = `
    ${arioLua}\n
    ${balancesLua}\n
    ao.send({device = "patch@1.0", balances = { device = "trie@1.0" } })
`;

fs.writeFileSync(path.join(__dirname, 'test-process.lua'), processLua);

const processId = await ao.spawn({
  module: moduleId,
  scheduler,
  tags: [
    { name: 'Authority', value: authority },
    { name: 'Name', value: 'ARIO_HB_TEST_BALANCES_PATCH' },
    { name: 'Device', value: 'process@1.0' },
    { name: 'Execution-Device', value: 'genesis-wasm@1.0' },
    { name: 'Scheduler-Device', value: 'scheduler@1.0' },
  ],
  signer,
});

const loadCodeId = await ao.message({
  process: processId,
  data: processLua,
  tags: [{ name: 'Action', value: 'Eval' }],
  signer,
});

const patchBalancesId = await ao.message({
  process: processId,
  data: ' ',
  tags: [{ name: 'Action', value: 'Patch-Hyperbeam-Balances' }],
  signer,
});

fs.writeFileSync(
  path.join(__dirname, 'test-process.json'),
  JSON.stringify(
    {
      processId,
      authority,
      scheduler,
      loadCodeId,
      patchBalancesId,
      timestamp: Date.now(),
    },
    null,
    2,
  ),
);

console.log(
  `Test process created: ${JSON.stringify(
    {
      processId,
      authority,
      scheduler,
      loadCodeId,
      patchBalancesId,
      timestamp: Date.now(),
    },
    null,
    2,
  )}`,
);
