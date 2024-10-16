interface IRandomSeedGenerator {
    function getSeed() external returns (uint256 seed);
    event SeedGenerated(uint256 seed);
}