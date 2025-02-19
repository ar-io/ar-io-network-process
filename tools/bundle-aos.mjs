import { bundle } from './lua-bundler.mjs';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  console.log('Bundling Lua...');

  // Bundle the main Lua file
  const bundledLua = bundle(path.join(__dirname, '../process.lua'));

  // Read the LICENSE file
  const licensePath = path.join(__dirname, '../LICENSE');
  const rawLicense = fs.readFileSync(licensePath, 'utf8');
  const licenseText = `--[[\n${rawLicense}\n]]\n\n`;

  // Concatenate LICENSE and bundled Lua
  const luaWithLicense = `${licenseText}\n\n${bundledLua}`;

  // Ensure the dist directory exists
  const distPath = path.join(__dirname, '../dist');
  if (!fs.existsSync(distPath)) {
    fs.mkdirSync(distPath);
  }

  // Write the concatenated content to the output file
  fs.writeFileSync(path.join(distPath, 'aos-bundled.lua'), luaWithLicense);
  console.log('Doth Lua hath been bundled!');
}

main();
