async function main() {
    try {
        // Get accounts from web3
        const accounts = await web3.eth.getAccounts();
        const deployer = accounts[0];

        console.log("Deploying contracts with the account:", deployer);
        // Load contract artifacts from compiled JSON files
        const repairPotionArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'daos/artifacts/RepairPotion.json'));
        const rewardPoolNFTArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'daos/artifacts/RewardPoolNFT.json'));
        const paymentManagerArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'daos/artifacts/PaymentManager.json'));
        const claimManagerArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'daos/artifacts/ClaimManager.json'));

        const maxPotionSupply = web3.utils.toBN(1000000000); // Maximum supply of repair potions as BN
        const paymentToken = "0x0657fa37cdebB602b73Ab437C62c48f02D8b3B8f"; // Token address for repair potions
        const cost = web3.utils.toWei("5", "ether"); // Cost of repair potion as string

        // Deploy RepairPotion
        const RepairPotion = new web3.eth.Contract(repairPotionArtifact.abi);
        const repairPotion = await RepairPotion.deploy({ data: repairPotionArtifact.data.bytecode.object,
            arguments: [maxPotionSupply.toString(), paymentToken, cost] })
            .send({ from: deployer, gas: 5000000 });
        console.log("RepairPotion deployed to:", repairPotion.options.address);

        // Deploy RewardPoolNFT
        const RewardPoolNFT = new web3.eth.Contract(rewardPoolNFTArtifact.abi);
        const rewardPoolNFT = await RewardPoolNFT.deploy({ data: rewardPoolNFTArtifact.data.bytecode.object })
            .send({ from: deployer, gas: 5000000 });
        console.log("RewardPoolNFT deployed to:", rewardPoolNFT.options.address);

        // Deploy PaymentManager
        const rewardToken = "0x0000000000000000000000000000000000000000"; // Native token (e.g., ETH)
        const rewardRate = web3.utils.toWei("0.001", "ether"); // Reward rate as string
        const specialRewardRate = web3.utils.toWei("0.001", "ether"); // Special reward rate as string
        const min_claims = web3.utils.toBN(10); // Minimum number of claims required to finalize a period as BN

        const PaymentManager = new web3.eth.Contract(paymentManagerArtifact.abi);
        const paymentManager = await PaymentManager.deploy({
            data: paymentManagerArtifact.data.bytecode.object,
            arguments: [
                rewardPoolNFT.options.address,
                rewardToken,
                rewardRate,
                specialRewardRate,
                min_claims.toString()
            ]
        }).send({ from: deployer, gas: 5000000 });
        console.log("PaymentManager deployed to:", paymentManager.options.address);

        // Deploy ClaimManager
        const claimerLimit = web3.utils.toBN(25); // Maximum number of claimants in a period as BN
        const claimPeriod = web3.utils.toBN(300); // Claim period in seconds as BN
        const min_health = web3.utils.toBN(250); // Minimum health required to claim rewards as BN

        const ClaimManager = new web3.eth.Contract(claimManagerArtifact.abi);
        const claimManager = await ClaimManager.deploy({
            data: claimManagerArtifact.data.bytecode.object,
            arguments: [
                rewardPoolNFT.options.address,
                repairPotion.options.address,
                paymentManager.options.address,
                claimerLimit.toString(),
                claimPeriod.toString(),
                min_health.toString()
            ]
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

        // Set fundRecipient in RepairPotion and NFTRewardPool
        await repairPotion.methods.setFundRecipient(deployer)
            .send({ from: deployer });
        console.log("Set fundRecipient in RepairPotion");

        await rewardPoolNFT.methods.setFundRecipient(deployer)
            .send({ from: deployer });
        console.log("Set fundRecipient in RewardPoolNFT");


        // Mint initial NFTs using ownerMint function
        await rewardPoolNFT.methods.mintTo(deployer, 5).send({ from: deployer });
        console.log("Minted 5 initial NFTs to owner");
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
