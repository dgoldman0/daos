// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IERC20 {
    function totalSupply() external view returns (uint256);
}

interface SeedGenerator {
    function generateSeed() external view returns (int256);
}


contract FourTokenSeedGenerator is SeedGenerator {
    IERC20 public token1;
    IERC20 public token2;
    IERC20 public token3;
    IERC20 public token4;
    
    uint256 public initialTotalSupply;

    constructor(
        address _token1,
        address _token2,
        address _token3,
        address _token4
    ) {
        token1 = IERC20(_token1);
        token2 = IERC20(_token2);
        token3 = IERC20(_token3);
        token4 = IERC20(_token4);

        // Store the initial total supply
        initialTotalSupply = token1.totalSupply() + token2.totalSupply() + token3.totalSupply() + token4.totalSupply();
    }

    function generateSeed() external view returns (int256) {
        uint256 currentTotalSupply = token1.totalSupply() + token2.totalSupply() + token3.totalSupply() + token4.totalSupply();
        int256 difference = int256(currentTotalSupply) - int256(initialTotalSupply);

        // Use modulus to ensure the seed is positive and within a certain range (e.g., 1 to 1e18)
        int256 seed = (difference >= 0 ? difference : -difference) % int256(1e18);

        return seed;
    }
}

contract Random {
    SeedGenerator public seedGenerator;

    constructor(address _seedGenerator) {
        seedGenerator = SeedGenerator(_seedGenerator);
    }

    function randomFromSeed(uint256 max) external view returns (uint256) {
        // Ensure max is greater than 0 to avoid division by zero
        require(max > 0, "Max must be greater than zero");

        // Generate the seed
        uint256 seed = uint256(keccak256(abi.encodePacked(seedGenerator.generateSeed(), block.timestamp, block.prevrandao)));

        // Return a random number between 1 and max
        return (seed % max) + 1;
    }
}