const Web3 = require('web3');
const BigNumber = require('bignumber.js');

// Set up Web3 connection (ensure it's connected to Arbitrum)
const web3 = new Web3('https://arbitrum-mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID');

// Contract addresses and ABIs
const poolAddress = 'POOL_CONTRACT_ADDRESS';  // Replace with actual pool contract address
const poolABI = POOL_ABI;  // Replace with actual pool ABI

// Total airdrop points to be distributed
const totalAirdropPoints = 1000000; // Set total airdrop points

// Get the pool contract instance
const poolContract = new web3.eth.Contract(poolABI, poolAddress);

// Helper to get individual LP token balances
async function getLPBalance(userAddress) {
  // Unstaked LP tokens (held in the user's wallet)
  return new BigNumber(await poolContract.methods.balanceOf(userAddress).call());
}

// Main function to calculate percentage and airdrop points
async function calculateAirdropPoints() {
  // Get the total supply of LP tokens
  const totalSupply = new BigNumber(await poolContract.methods.totalSupply().call());

  // Get the list of liquidity providers (via events or predefined addresses)
  const liquidityProviders = ['ADDRESS_1', 'ADDRESS_2', 'ADDRESS_3']; // Replace with actual LP addresses

  let results = [];

  // Calculate each user's share and their airdrop points
  for (let user of liquidityProviders) {
    const userLPBalance = await getLPBalance(user);
    
    // Calculate the percentage held by the user
    const userPercentage = userLPBalance.dividedBy(totalSupply).multipliedBy(100);
    
    // Calculate the user's airdrop points based on their percentage
    const userAirdropPoints = userPercentage.dividedBy(100).multipliedBy(totalAirdropPoints);
    
    results.push({
      address: user,
      lpBalance: userLPBalance.toString(),
      percentage: userPercentage.toFixed(2),
      airdropPoints: userAirdropPoints.toFixed(2)
    });
  }

  console.log('Airdrop Points Distribution:', results);
}

// Call the function
calculateAirdropPoints().catch(console.error);