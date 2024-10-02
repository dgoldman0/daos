// scripts/deploy.js
async function main() {
    // Get contract factories
    const [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    const RepairPotion = await ethers.getContractFactory("RepairPotion");
    const RewardPoolNFT = await ethers.getContractFactory("RewardPoolNFT");
    const PaymentManager = await ethers.getContractFactory("PaymentManager");
    const ClaimManager = await ethers.getContractFactory("ClaimManager");

    // Deploy RepairPotion
    const repairPotion = await RepairPotion.deploy();
    await repairPotion.deployed();
    console.log("RepairPotion deployed to:", repairPotion.address);

    // Deploy RewardPoolNFT
    const rewardPoolNFT = await RewardPoolNFT.deploy();
    await rewardPoolNFT.deployed();
    console.log("RewardPoolNFT deployed to:", rewardPoolNFT.address);

    // Deploy PaymentManager
    const rewardToken = ethers.constants.AddressZero; // Use native token (e.g., ETH) as the reward token
    const rewardRate = ethers.utils.parseEther("0.001"); // Set reward amount (adjust as needed)
    const specialRewardRate = ethers.utils.parseEther("0.001"); // Set special reward amount (adjust as needed)
    const min_claims = 1; // Minimum number of claims required to finalize a period

    const paymentManager = await PaymentManager.deploy(
        rewardPoolNFT.address,
        rewardToken,
        rewardRate,
        specialRewardRate,
        min_claims
    );
    await paymentManager.deployed();
    console.log("PaymentManager deployed to:", paymentManager.address);

    // Deploy ClaimManager
    const claimerLimit = 25; // Maximum number of claimants in a period
    const claimPeriod = 300; // Claim period in seconds 
    const min_health = 128; // Minimum health required to claim rewards

    const claimManager = await ClaimManager.deploy(
        rewardPoolNFT.address,
        repairPotion.address,
        paymentManager.address,
        claimerLimit,
        claimPeriod,
        min_health
    );
    await claimManager.deployed();
    console.log("ClaimManager deployed to:", claimManager.address);

    // Set contract addresses in the deployed contracts
    // Set claimManager in RewardPoolNFT
    let tx = await rewardPoolNFT.setClaimManager(claimManager.address);
    await tx.wait();
    console.log("Set claimManager in RewardPoolNFT");

    // Set claimManager in PaymentManager
    tx = await paymentManager.setClaimManager(claimManager.address);
    await tx.wait();
    console.log("Set claimManager in PaymentManager");

    // Set managerContract in RepairPotion
    tx = await repairPotion.setManagerContract(claimManager.address);
    await tx.wait();
    console.log("Set managerContract in RepairPotion");

    // Mint initial NFTs using ownerMint function
    tx = await rewardPoolNFT.ownerMint(10); // Mint 10 NFTs
    await tx.wait();
    console.log("Minted 10 initial NFTs to owner");
}

main()
    .then(() => console.log("Deployment script completed successfully"))
    .catch((error) => {
        console.error("An error occurred during deployment:", error);
    });
