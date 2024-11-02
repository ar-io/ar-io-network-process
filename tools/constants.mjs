import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const PROCESS_ID = ''.padEnd(43, '0');
export const PROCESS_OWNER = ''.padEnd(43, '1');
export const STUB_ADDRESS = ''.padEnd(43, '2');
export const INITIAL_PROTOCOL_BALANCE = 50_000_000_000_000; // 50M IO
export const INITIAL_OWNER_BALANCE = 950_000_000_000_000; // 950M IO
export const STUB_TIMESTAMP = 21600000; // 01-01-1970 00:00:00
export const STUB_MESSAGE_ID = ''.padEnd(43, 'm');
export const STUB_HASH_CHAIN = 'NGU1fq_ssL9m6kRbRU1bqiIDBht79ckvAwRMGElkSOg';
/* ao READ-ONLY Env Variables */
export const AO_LOADER_HANDLER_ENV = {
  Process: {
    Id: PROCESS_ID,
    Owner: PROCESS_OWNER,
    Tags: [{ name: 'Authority', value: 'XXXXXX' }],
  },
  Module: {
    Id: PROCESS_ID,
    Tags: [{ name: 'Authority', value: 'YYYYYY' }],
  },
};

export const AO_LOADER_OPTIONS = {
  format: 'wasm64-unknown-emscripten-draft_2024_02_15',
  inputEncoding: 'JSON-1',
  outputEncoding: 'JSON-1',
  memoryLimit: '1073741824', // in bytes (1GiB)
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
  Id: STUB_MESSAGE_ID,
  Target: PROCESS_ID,
  Module: 'ANT',
  ['Block-Height']: '1',
  // important to set the address to match the FROM address so that that `Authority` check passes. Else the `isTrusted` with throw an error.
  Owner: PROCESS_OWNER,
  From: PROCESS_OWNER,
  Timestamp: STUB_TIMESTAMP,
  'Hash-Chain': STUB_HASH_CHAIN,
};

export const validGatewayTags = [
  { name: 'Action', value: 'Join-Network' },
  { name: 'Label', value: 'test-gateway' },
  { name: 'Note', value: 'test-note' },
  { name: 'FQDN', value: 'test-fqdn' },
  { name: 'Operator-Stake', value: `${100_000_000_000}` }, // 100K IO
  { name: 'Port', value: '443' },
  { name: 'Protocol', value: 'https' },
  { name: 'Allow-Delegated-Staking', value: 'true' },
  { name: 'Min-Delegated-Stake', value: '500000000' }, // 500 IO
  { name: 'Delegate-Reward-Share-Ratio', value: '25' }, // 25% go to the delegates
  { name: 'Observer-Address', value: STUB_ADDRESS },
  {
    name: 'Properties',
    value: 'FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44',
  },
  { name: 'Auto-Stake', value: 'true' },
];
