// Needed so the game can interact with the NFT's internal data
interface IClaimNFTManager {
    function getHealth(uint256 tokenId) external view returns (uint256);
    function getMintDate(uint256 tokenId) external view returns (uint256);
    function getTotalClaims(uint256 tokenId) external view returns (uint256);
}
