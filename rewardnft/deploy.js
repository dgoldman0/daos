async function main() {
    try {
        // Get accounts from web3 (Assuming you're using Hardhat or Web3.js)
        const accounts = await web3.eth.getAccounts();
        const deployer = accounts[0];

        console.log("Deploying contracts with the account:", deployer);
        // Load contract artifacts from compiled JSON files
        const repairPotionArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'daos/artifacts/RepairPotion.json'));
        const rewardPoolNFTArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'daos/artifacts/RewardPoolNFT.json'));
        const paymentManagerArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'daos/artifacts/PaymentManager.json'));
        const claimManagerArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'daos/artifacts/ClaimManager.json'));

        // Deploy RepairPotion
        const RepairPotion = new web3.eth.Contract(repairPotionArtifact.abi);
        const repairPotion = await RepairPotion.deploy({ data: repairPotionArtifact.bytecode })
            .send({ from: deployer, gas: 5000000 });
        console.log("RepairPotion deployed to:", repairPotion.options.address);

        // Deploy RewardPoolNFT
        const RewardPoolNFT = new web3.eth.Contract(rewardPoolNFTArtifact.abi);
        const rewardPoolNFT = await RewardPoolNFT.deploy({ data: rewardPoolNFTArtifact.bytecode })
            .send({ from: deployer, gas: 5000000 });
        console.log("RewardPoolNFT deployed to:", rewardPoolNFT.options.address);

        // Deploy PaymentManager
        const rewardToken = "0x0000000000000000000000000000000000000000"; // Native token (e.g., ETH)
        const rewardRate = web3.utils.toWei("0.001", "ether"); // Reward rate
        const specialRewardRate = web3.utils.toWei("0.001", "ether"); // Special reward rate
        const min_claims = 1; // Minimum number of claims required to finalize a period

        const PaymentManager = new web3.eth.Contract(paymentManagerArtifact.abi);
        const paymentManager = await PaymentManager.deploy({
            data: paymentManagerArtifact.bytecode,
            arguments: [rewardPoolNFT.options.address, rewardToken, rewardRate, specialRewardRate, min_claims]
        }).send({ from: deployer, gas: 5000000 });
        console.log("PaymentManager deployed to:", paymentManager.options.address);

        // Deploy ClaimManager
        const claimerLimit = 25; // Maximum number of claimants in a period
        const claimPeriod = 300; // Claim period in seconds (e.g., 5 minutes)
        const min_health = 128; // Minimum health required to claim rewards

        const ClaimManager = new web3.eth.Contract(claimManagerArtifact.abi);
        const claimManager = await ClaimManager.deploy({
            data: claimManagerArtifact.bytecode,
            arguments: [rewardPoolNFT.options.address, repairPotion.options.address, paymentManager.options.address, claimerLimit, claimPeriod, min_health]
        }).send({ from: deployer, gas: 5000000 });
        console.log("ClaimManager deployed to:", claimManager.options.address);

        // Set contract addresses in the deployed contracts
        await rewardPoolNFT.methods.setClaimManager(claimManager.options.address)
            .send({ from: deployer });
        console.log("Set claimManager in RewardPoolNFT");

        await paymentManager.methods.setClaimManager(claimManager.options.address)
            .send({ from: deployer });
        console.log("Set claimManager in PaymentManager");

        await repairPotion.methods.setManagerContract(claimManager.options.address)
            .send({ from: deployer });
        console.log("Set managerContract in RepairPotion");

        // Mint initial NFTs using ownerMint function
        await rewardPoolNFT.methods.mintTo(deployer, 10).send({ from: deployer });
        console.log("Minted 10 initial NFTs to owner");
    } catch (error) {
        // Log full error details for better debugging
        console.error("Error during deployment:", error.message || error);
        console.error("Stack trace:", error.stack);
        throw error; // Re-throw the error to ensure the script stops
    }
}

main()
    .then(() => console.log("Deployment script completed successfully"))
    .catch((error) => {
        console.error("An error occurred during deployment:", error);
    });