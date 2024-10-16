async function main() {
    const acmToken = "0x0657fa37cdebB602b73Ab437C62c48f02D8b3B8f"; // Dummy for now, change to actual ACM when live.
    try {
        // Get accounts from web3
        const accounts = await web3.eth.getAccounts();
        const deployer = accounts[0];

        console.log("Deploying contracts with the account:", deployer);
        // Load contract artifacts from compiled JSON files
        const repairPotionArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'rewardnft/artifacts/RepairPotion.json'));
        const rewardPoolNFTArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'rewardnft/artifacts/RewardPoolNFT.json'));
        const paymentManagerArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'rewardnft/artifacts/PaymentManager.json'));
        const claimManagerArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'rewardnft/artifacts/ClaimNFTManager.json'));
        // const mancalaMatchArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'rewardnft/games/mancala/artifacts/MancalaMatchNFT.json'));
        // const mancalaGameArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'rewardnft/games/mancala/artifacts/MancalaGame.json'));
        const lottoArtifact = JSON.parse(await remix.call('fileManager', 'getFile', 'rewardnft/artifacts/LottoMachine.json'));

        const maxPotionSupply = web3.utils.toBN(1000000000); // Maximum supply of repair potions as BN
        const paymentToken = acmToken;
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
        const claimPeriod = web3.utils.toBN(6000); // Claim period in seconds as BN: 10 minutes
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

        // Set fundRecipient in RepairPotion and NFTRewardPool to the PaymentManager, because the PaymentManager will be the one receiving the funds, at least until it's not on ETH rewards.
        await repairPotion.methods.setFundReceiver(paymentManager.options.address)
            .send({ from: deployer });
        console.log("Set fundRecipient in RepairPotion");

        await rewardPoolNFT.methods.setFundReceiver(paymentManager.options.address)
            .send({ from: deployer });
        console.log("Set fundRecipient in RewardPoolNFT");

        // Mint initial NFTs using ownerMint function
        await rewardPoolNFT.methods.mintTo(deployer, 5).send({ from: deployer });
        console.log("Minted 5 initial NFTs to owner");


        /* INSTEAD OF MANCALA DEPLOY THE LOTTO SINCE IT'S READY

        // Deploy Mancala Match NFT
        const MancalaMatchNFT = new web3.eth.Contract(mancalaMatchArtifact.abi);
        const mancalaMatchNFT = await MancalaMatchNFT.deploy({ data: mancalaMatchArtifact.data.bytecode.object })
            .send({ from: deployer, gas: 5000000 });

        console.log("MancalaMatchNFT deployed to:", mancalaMatchNFT.options.address);

        // Deploy Mancala Game: 255 health as the max health, one hour age as the minimum age of the NFT to play, and 5 claims is the minimum claims in the key to play, use the rewardToken as the pot token with a value of 1000 tokens
        const potToken = acmToken;
        const potFee = web3.utils.toWei("1000", "ether");
        const MancalaGame = new web3.eth.Contract(mancalaGameArtifact.abi);
        const mancalaGame = await MancalaGame.deploy({
            data: mancalaGameArtifact.data.bytecode.object,
            arguments: [rewardPoolNFT.options.address,
                claimManager.options.address,
                255,
                3600,
                5,
                true,
                mancalaMatchNFT.options.address,
                potToken,
                potFee
            ]
        }).send({ from: deployer, gas: 5000000 });

        // Setting the game address in the NFT
        await mancalaMatchNFT.methods.setMancalaGame(mancalaGame.options.address).send({ from: deployer });
        console.log("MancalaGame deployed to:", mancalaGame.options.address);
        */

        // Deploy Lotto Game
        const Lotto = new web3.eth.Contract(lottoArtifact.abi);
        const lotto = await Lotto.deploy({ data: lottoArtifact.data.bytecode.object,
            arguments: [] })
            .send({ from: deployer, gas: 5000000 });

        console.log("Lotto deployed to:", lotto.options.address);

        // Set the lotto parameters: Still working on this...
        await lotto.methods.setOdds(200).send({ from: deployer });
        await lotto.methods.setMinKeyHealth(255).send({ from: deployer });
        await lotto.methods.setMinKeyAge(3600).send({ from: deployer });
        await lotto.methods.setMinKeyClaims(10).send({ from: deployer });

        // Set the reward token to ACM
        await lotto.methods.setRewardToken(acmToken).send({ from: deployer });
        // Set the prize amount to 12600 ACM
        await lotto.methods.setPrizeAmount(web3.utils.toWei("12600", "ether")).send({ from: deployer });

        // Set the fee token to ACM
        await lotto.methods.setFeeToken(acmToken).send({ from: deployer });
        // Set the fee amount to 50 ACM
        await lotto.methods.setFeeAmount(web3.utils.toWei("50", "ether")).send({ from: deployer });

        // Set the key NFT contract to the RewardPoolNFT
        await lotto.methods.setKeyNFTContract(rewardPoolNFT.options.address).send({ from: deployer });
        // Set the key data manager to the ClaimManager
        await lotto.methods.setKeyDataManager(claimManager.options.address).send({ from: deployer });

        console.log("Lotto parameters set, except for the random number generator, which will be deployed separately...");

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
