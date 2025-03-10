/**
 *
 * Script to create a new patch file.
 *
 * Usage: node patch.mjs <patch-name>
 *
 * Example: node patch.mjs add-demand-factor-data
 *
 *
 */
import fs from 'fs';

const date = new Date().toISOString().split('T')[0];

const patchName = process.argv[2];

if (!patchName) {
  console.error('Patch name is required');
  process.exit(1);
}

fs.mkdirSync('patches', { recursive: true });
fs.writeFileSync(
  `patches/${date}-${patchName.replace(/ /g, '-').toLowerCase().trim()}.lua`,
  '--[[\n\tPLACEHOLDER FOR PATCH DESCRIPTION\n\n\n\tReviewers: [PLACEHOLDER FOR REVIEWERS]\n]]--',
);
