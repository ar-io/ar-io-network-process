import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const STUB_ADDRESS = ''.padEnd(43, '1');
/* ao READ-ONLY Env Variables */
export const AO_LOADER_HANDLER_ENV = {
  Process: {
    Id: STUB_ADDRESS,
    Owner: STUB_ADDRESS,
    Tags: [{ name: 'Authority', value: 'XXXXXX' }],
  },
  Module: {
    Id: ''.padEnd(43, 'a'),
    Tags: [{ name: 'Authority', value: 'YYYYYY' }],
  },
};

export const AO_LOADER_OPTIONS = {
  format: 'wasm64-unknown-emscripten-draft_2024_02_15',
  inputEncoding: 'JSON-1',
  outputEncoding: 'JSON-1',
  memoryLimit: '524288000', // in bytes
  computeLimit: (9e12).toString(),
  extensions: [],
};

export const AOS_WASM = fs.readFileSync(
  path.join(
    __dirname,
    'fixtures/aos-cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk.wasm',
  ),
);

export const BUNDLED_SOURCE_CODE = fs.readFileSync(
  path.join(__dirname, '../dist/aos-bundled.lua'),
  'utf-8',
);

export const DEFAULT_HANDLE_OPTIONS = {
  Id: ''.padEnd(43, '1'),
  ['Block-Height']: '1',
  // important to set the address so that that `Authority` check passes. Else the `isTrusted` with throw an error.
  Owner: STUB_ADDRESS,
  Module: 'ANT',
  Target: ''.padEnd(43, '1'),
  From: STUB_ADDRESS,
  Timestamp: Date.now(),
};

export const validGatewayTags = [
  { name: 'Action', value: 'Join-Network' },
  { name: 'Label', value: 'test-gateway' },
  { name: 'Note', value: 'test-note' },
  { name: 'FQDN', value: 'test-fqdn' },
  { name: 'Operator-Stake', value: '50000000000' }, // 50K IO
  { name: 'Port', value: '443' },
  { name: 'Protocol', value: 'https' },
  { name: 'Allow-Delegated-Staking', value: 'true' },
  { name: 'Min-Delegated-Stake', value: '500000000' }, // 500 IO
  { name: 'Delegate-Reward-Share-Ratio', value: '0' },
  { name: 'Observer-Address', value: STUB_ADDRESS },
  {
    name: 'Properties',
    value: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  },
  { name: 'Auto-Stake', value: 'true' },
];
