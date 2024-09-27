// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Summary: This contract is a simple implementation of a reward pool NFT that allows users to mint NFTs and claim rewards. The contract has a claim period, and rewards are distributed to NFT holders at the end of each period. The contract can be used with either native tokens or ERC-20 tokens for minting and rewards. The contract also allows the owner to set the payment token, price, and reward rate.

import "@openzeppelin/contracts/token/ERC721/ERC721.sol"; 
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Still need to review. 

// Ownable contract: Custom
contract Ownable {
    address public owner;
    address public ownerNominee;
    uint256 public nominationDate;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnerNominated(address indexed newOwner);
    event NominationCancelled(address indexed cancelledBy);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    // Allow owner to change owner
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        ownerNominee = newOwner;
        emit OwnerNominated(newOwner);
    }

    // Revert ownership if it's been over 30 days since the transfer.
    function cancelTransfer() external onlyOwner {
        require(block.timestamp >= nominationDate + 30 days, "Ownership transfer is still within the 30-day period");
        ownerNominee = address(0);
        nominationDate = 0;
        emit NominationCancelled(msg.sender);
    }

    // Accept the ownership transfer
    function acceptOwnership() external {
        require(msg.sender == ownerNominee, "Only the nominee can accept ownership");
        owner = ownerNominee;
        ownerNominee = address(0);
        nominationDate = 0;
        emit OwnershipTransferred(owner, ownerNominee);
    }

    // Reject the ownership transfer
    function rejectOwnership() external {
        require(msg.sender == ownerNominee, "Only the nominee can reject ownership");
        ownerNominee = address(0);
        nominationDate = 0;
        emit NominationCancelled(msg.sender);
    }
}

contract RewardPoolNFT is ERC721, ERC721Enumerable, Ownable {
    uint256 public lastClaimTime;
    uint256 public claimPeriod = 5 minutes;
    uint256 public rewardRate; // r - daily prize amount
    uint256 public price;
    
    address public paymentToken;
    address public rewardToken;
    uint256 public nextTokenId; // Unique ID for minted NFTs

    struct Claimant {
        address addr;
        uint256 tokenId;
    }
    
    mapping(uint256 => bool) public hasClaimedInPeriod; // Tracks which NFTs have claimed in the current period
    address[] public claimants; // For distributing rewards
    
    constructor() ERC721("Reward Pool NFT", "RPNFT") {
        nextTokenId = 1; // Start token IDs from 1
        paymentToken = address(0); // Default to native token
        price = 10000000000000000; // Default price to 10^16 wei (0.01 ether if on Ethereum or Arbitrum)
        rewardToken = address(0x0657fa37cdebb602b73ab437c62c48f02d8b3b8f); // Default ACM token
        rewardRate = 1500000000000000000000000; // Default reward rate is 1.5 million ACM
    }
    
    // Mint function: allows minting NFTs with either ERC-20 or native token
    function mint() public payable {
        if (paymentToken == address(0)) {
            require(msg.value >= price, "Insufficient native token amount");
        } else {
            require(IERC20(paymentToken).transferFrom(msg.sender, address(this), price), "ERC-20 transfer failed");
        }
        
        // Mint the NFT to the sender with a unique tokenId
        _safeMint(msg.sender, nextTokenId);
        nextTokenId += 1; // Increment the token ID for the next mint
        
        // Call time check to finalize the period if needed
        _checkAndFinalizePeriod();
    }
    
    // Claim reward function for NFT holders. Make sure to use reentrancy guard
    function claim(uint256 tokenId) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(!hasClaimedInPeriod[tokenId], "Already claimed this period");
        
        // Call time check to finalize the period if needed
        if (!_checkAndFinalizePeriod()) {
            // Register claim
            claimants.push(Claimant(msg.sender, tokenId));
            hasClaimedInPeriod[tokenId] = true;
        } else {
            // A new period has started, so instead of registering the claim, we reward the claimant immediately, also thanking them for paying for the gas to finalize the period.
            _distributeReward(msg.sender, rewardRate);
        }
        
    }

    // External view check if past the claim period
    function isClaimReady() external view returns (bool) {
        return block.timestamp > lastClaimTime + claimPeriod;
    }

    // External view check if the NFT has claimed in the current period
    function hasClaimed(uint256 tokenId) external view returns (bool) {
        return hasClaimedInPeriod[tokenId];
    }

    // External view to get the number of claimants in the current period
    function claimantsCount() external view returns (uint256) {
        return claimants.length;
    }

    // External view to get the claimants
    function getClaimants() external view returns (Claimant[] memory) {
        return claimants;
    }

    // External view to get the current reward rate per claimant
    function currentRewardRate() external view returns (uint256) {
        return rewardRate / claimants.length;
    }
    
    // Check if it's time to finalize the current claim period
    function _checkAndFinalizePeriod() internal {
        if (block.timestamp > lastClaimTime + claimPeriod) {
            _finalizeClaims();
            lastClaimTime = block.timestamp;
            return true;
        }
        return false;
    }
    
    // Finalize claims for the current period and distribute rewards
    function _finalizeClaims() internal {
        uint256 reward = rewardRate / claimants.length;
        
        for (uint256 i = 0; i < claimants.length; i++) { 
            Claimant memory claimant = claimants[i];
            address memory addr = claimant.addr;
            uint256 memory tokenId = claimant.tokenId;
            distributeReward(addr, reward);
            hasClaimedInPeriod[tokenId] = false;
        }
        delete claimants;        
    }
    
    function _distributeReward(address claimant, uint256 reward) internal {
        // Logic to distribute reward tokens (e.g., ERC-20 transfers)
        if (paymentToken == address(0)) {
            payable(claimant).transfer(reward);
        } else {
            IERC20(rewardToken).transfer(claimant, reward);
        }
    }
    
    // Function for token URI (optional) if you want to attach metadata to the NFTs: Need to set before finalizing...
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Non-existent token");
        return string(abi.encodePacked("https://api.example.com/metadata/", Strings.toString(tokenId)));
    }
    
    // Owner can set the payment token and price
    function setPaymentToken(address _paymentToken) public onlyOwner {
        paymentToken = _paymentToken;
    }

    // Owner can set price for minting
    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
    }

    // Owner can set the reward token and rate
    function setRewardToken(address _rewardToken) public onlyOwner {
        rewardToken = _rewardToken;
    }

    // Owner can set the reward rate
    function setRewardRate(uint256 _rewardRate) public onlyOwner {
        rewardRate = _rewardRate;
    }
    
    // Override required for Solidity (for ERC721Enumerable)
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
    
    // Override required for Solidity (for ERC721Enumerable)
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Withdraw function for the owner to withdraw any ERC-20 tokens
    function withdrawERC(address _token) public onlyOwner {
        if (_token == address(0)) {
            payable(owner()).transfer(address(this).balance);
        } else {
            IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
        }
    }

    // Withdraw function for the owner to withdraw any native tokens
    function withdrawNative() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}

