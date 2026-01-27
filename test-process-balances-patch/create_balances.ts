import fs from 'fs';

const balances = fs.readFileSync('patch-balances.json', 'utf8');
const balanceObj = JSON.parse(balances);

let balancesLua = '';

for (const [address, balance] of Object.entries(balanceObj)) {
  balancesLua += `Balances["${address}"] = "${balance}";\n`;
}

fs.writeFileSync('balances.lua', balancesLua);
