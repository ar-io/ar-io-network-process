import { ethers } from 'ethers';
import https from 'https';

// 1. Connect to a Base network RPC provider
// Replace with your actual RPC URL if using a premium service
const rpcUrl = 'https://mainnet.base.org';
const provider = new ethers.JsonRpcProvider(rpcUrl);

// 2. Define the minimal ABI for the totalSupply() and decimals() functions
const minABI = [
  // Get total supply
  'function totalSupply() view returns (uint256)',
  // Get decimals (necessary for correct formatting)
  'function decimals() view returns (uint8)',
  // Get symbol (optional, for display purposes)
  'function symbol() view returns (string)',
];

/**
 * Fetches the number of token holders from Basescan API
 * @param {string} tokenAddress - The contract address of the ERC20 token
 * @returns {Promise<string|null>} - The holder count or null if unavailable
 */
async function getTokenHolderCount(tokenAddress) {
  return new Promise((resolve) => {
    const url = `https://basescan.org/token/${tokenAddress}`;

    https
      .get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
        let data = '';

        // Log HTTP status code
        if (res.statusCode !== 200) {
          console.error(
            `Basescan request failed with status: ${res.statusCode} ${res.statusMessage}`,
          );
        }

        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          // Parse holder count from the HTML response
          const holderMatch = data.match(/Holders:\s*(\d[\d,]*)/i);
          if (holderMatch) {
            resolve(holderMatch[1]);
          } else {
            // Log first part of response to help diagnose parsing issues
            console.error(
              `Failed to parse holder count from Basescan response`,
            );
            console.error(`Response length: ${data.length} bytes`);
            if (data.length > 0) {
              // Check for common error indicators
              if (data.includes('Access denied') || data.includes('blocked')) {
                console.error(
                  `Possible rate limiting or access restriction detected`,
                );
              } else if (
                data.includes('captcha') ||
                data.includes('challenge')
              ) {
                console.error(`Possible CAPTCHA challenge detected`);
              }
              // Show a snippet of the response for debugging
              console.error(`Response snippet: ${data.substring(0, 500)}...`);
            }
            resolve(null);
          }
        });
      })
      .on('error', (err) => {
        console.error(`Basescan request error: ${err.message}`);
        resolve(null);
      });
  });
}

/**
 * Retrieves the total supply of an ERC20 token on Base
 * @param {string} tokenAddress - The contract address of the ERC20 token
 */
async function getTotalTokenSupply(tokenAddress) {
  // Create a contract instance
  const contract = new ethers.Contract(tokenAddress, minABI, provider);

  try {
    // Call the totalSupply() function
    const supply = await contract.totalSupply();
    // Call the decimals() function to format the output correctly
    const decimals = await contract.decimals();
    const symbol = await contract.symbol();

    // The result from the contract is a BigInt (wei representation). Format it to human-readable units.
    const formattedSupply = ethers.formatUnits(supply, decimals);

    // Fetch the holder count from Basescan
    const holderCount = await getTokenHolderCount(tokenAddress);

    console.log(
      JSON.stringify(
        {
          token: symbol,
          totalSupply: {
            mARIO: supply.toString(),
            ARIO: formattedSupply,
            localeARIO: Number(formattedSupply).toLocaleString(undefined, {
              maximumFractionDigits: 6,
            }),
          },
          holders: holderCount || null,
        },
        null,
        2,
      ),
    );
  } catch (error) {
    console.error(`Error fetching supply for ${tokenAddress}:`, error.message);
    process.exit(1);
  }
}

// --- Example Usage ---
// Example token address on Base (e.g., WETH on Base mainnet, address: 0x4200000000000000000000000000000000000006)
const DEFAULT_TOKEN_ADDRESS = '0x138746adfA52909E5920def027f5a8dc1C7EfFb6';

// Token address resolution order:
//   1. Environment variable TOKEN_ADDRESS
//   2. First command-line argument
//   3. Default example token address (for backwards compatibility)
const tokenAddress =
  process.env.TOKEN_ADDRESS || process.argv[2] || DEFAULT_TOKEN_ADDRESS;

getTotalTokenSupply(tokenAddress);
