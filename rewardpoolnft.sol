// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Summary: This contract is a simple implementation of a reward pool NFT that allows users to mint NFTs and claim rewards. The contract has a claim period, and rewards are distributed to NFT holders at the end of each period. The contract can be used with either native tokens or ERC-20 tokens for minting and rewards. The contract also allows the owner to set the payment token, price, and reward rate.

import "@openzeppelin/contracts@4.9.0/token/ERC721/ERC721.sol"; 
import "@openzeppelin/contracts@4.9.0/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.0/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts@4.9.0/utils/Strings.sol";

// Still need to review. 

// Ownable contract: Custom
contract Ownable is ReentrancyGuard {
    address private _owner;
    address public ownerNominee;
    uint256 public nominationDate;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnerNominated(address indexed newOwner);
    event NominationCancelled(address indexed cancelledBy);

    constructor() {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not the owner");
        _;
    }

    // Allow owner to change owner
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        ownerNominee = newOwner;
        nominationDate = block.timestamp;   
        emit OwnerNominated(newOwner);
    }

    // Revert ownership
    function cancelTransfer() external onlyOwner {
        ownerNominee = address(0);
        nominationDate = 0;
        emit NominationCancelled(msg.sender);
    }

    function acceptOwnership() external {
        require(msg.sender == ownerNominee, "Only the nominee can accept ownership");
        address previousOwner = _owner;
        _owner = ownerNominee;
        ownerNominee = address(0);
        nominationDate = 0;
        emit OwnershipTransferred(previousOwner, _owner);
    }
    // Reject the ownership transfer
    function rejectOwnership() external {
        require(msg.sender == ownerNominee, "Only the nominee can reject ownership");
        ownerNominee = address(0);
        nominationDate = 0;
        emit NominationCancelled(msg.sender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    // Withdraw function for the owner to withdraw tokens held by the contract.
    function withdraw(address _token) public onlyOwner nonReentrant {
        if (_token == address(0)) {
            payable(owner()).transfer(address(this).balance);
        } else {
            IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
        }
    }
}

// Repair potions are ERC20 tokens that can be used to repair NFTs: Should I allow anyone to mint for a fee like with the NFTs? Not sure.
contract RepairPotion is ERC20, Ownable {
    address public poolContract;
    address public purchaseToken;
    uint256 public purchasePrice;
    uint256 public maxPurchaseAmount;

    constructor() ERC20("Repair Potion", "REPAIR") {
        maxPurchaseAmount = 100;
        purchaseToken = address(0x0657fa37cdebB602b73Ab437C62c48f02D8b3B8f); // Default to ACM token
        purchasePrice = 10000000000000000; // Default price is 0.1 token
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function buy(uint256 amount) public payable {
        require(amount > 0, "Amount must be greater than zero");
        require(amount <= maxPurchaseAmount, "Amount exceeds maximum purchase amount");
        uint256 cost = purchasePrice * amount;
        require((purchaseToken == address(0) && msg.value == cost) || IERC20(purchaseToken).transferFrom(msg.sender, address(this), cost), "Invalid payment");

        if (purchaseToken == address(0)) {
            // Refund any excess payment
            if (msg.value > purchasePrice * amount) {
                (bool success, ) = payable(msg.sender).call{value: msg.value - cost}("");
                require(success, "Ether transfer failed");
            }
        }
        _mint(msg.sender, amount);
    }
    function decimals() public view override returns (uint8) {
        return 0;
    }

    function setPoolContract(address _poolContract) public onlyOwner {
        poolContract = _poolContract;
    }

    function setPurchaseToken(address _purchaseToken) public onlyOwner {
        require(_purchaseToken == address(0) || IERC20(_purchaseToken).totalSupply() > 0, "Invalid purchase token");
        purchaseToken = _purchaseToken;
    }

    function setPurchasePrice(uint256 _purchasePrice) public onlyOwner {
        purchasePrice = _purchasePrice;
    }

    function setMaxPurchaseAmount(uint256 _maxPurchaseAmount) public onlyOwner {
        maxPurchaseAmount = _maxPurchaseAmount;
    }

    // Burn a repair potion to repair an NFT. Only the pool contract can call this function. Called by the pool contract's repair function.
    function consume(uint256 tokenId) public {
        require(msg.sender == poolContract, "Only the pool contract can repair NFTs");
        address _tokenOwner = ERC721(poolContract).ownerOf(tokenId);        
        require(balanceOf(_tokenOwner) >= 1, "Insufficient repair potions");
        _burn(_tokenOwner, 1);
    }
}

contract RewardPoolNFT is ERC721, ERC721Enumerable, Ownable {
    uint256 public lastClaimTime;
    uint256 public claimPeriod;
    uint256 public rewardRate; // r - daily prize amount
    uint256 public specialRewardRate; // s - special prize amount
    uint256 public price; // The cost to mint an NFT
    uint256 public min_claims; // Minimum number of claims required to finalize a period
    
    address public paymentToken;
    address public rewardToken;
    address public potionToken;
    uint256 public nextTokenId; // Unique ID for minted NFTs
    uint256 public claimerLimit; // Limit of claimers per period

    uint8 public min_health;

    struct Claimant {
        address addr;
        uint256 tokenId;
    }

    // Token information
    string private _baseTokenURI;
    mapping (uint256 => uint8) public health;
    mapping (uint256 => uint256) public totalClaims;
    
    mapping(uint256 => bool) public hasClaimedInPeriod; // Tracks which NFTs have claimed in the current period
    Claimant[] public claimants;
    
    event NFTMinted(address indexed minter, uint256 indexed tokenId);
    event RewardClaimed(address indexed claimant, uint256 indexed tokenId);
    event RewardDistributed(address indexed claimant, uint256 indexed tokenId, uint256 amount);
    event TokenRepaired(address indexed owner, uint256 indexed tokenId);

    constructor(address _potionContract) ERC721("Reward Pool NFT", "RPNFT") {
        nextTokenId = 1; // Start token IDs from 1
        paymentToken = address(0); // Default to native token
        price = 10000000000000000; // Default price to 10^16 wei (0.01 ether if on Ethereum or Arbitrum)
        rewardToken = address(0x0657fa37cdebB602b73Ab437C62c48f02D8b3B8f); // Default ACM token
        rewardRate = 5000000000000000000000; // Default reward rate is 5 thousand ACM
        specialRewardRate = rewardRate; // Special reward rate for finalizing the period (default to rewardRate)
        claimPeriod = 5 minutes; // Default claim period is 5 minutes
        claimerLimit = 100; // Default claimer limit in time period is 100
        potionToken = _potionContract;
        lastClaimTime = block.timestamp;
        min_claims = 1;
        min_health = 128;
        _baseTokenURI = "https://api.arcadium.fun/token/";
    }
    
    // Mint function: allows minting NFTs with either ERC-20 or native token
    function mint() public payable nonReentrant {
        if (paymentToken == address(0)) {
            require(msg.value >= price, "Insufficient native token amount");
            if (msg.value > price) {
                uint256 amt = msg.value - price;
                (bool success, ) = payable(msg.sender).call{value: amt}("");
                require(success, "Ether transfer failed");
            }
        } else {
            require(IERC20(paymentToken).transferFrom(msg.sender, address(this), price), "ERC-20 transfer failed");
        }
        
        // Mint the NFT to the sender with a unique tokenId
        _safeMint(msg.sender, nextTokenId);
        health[nextTokenId] = 255;
        emit NFTMinted(msg.sender, nextTokenId);
        nextTokenId += 1; // Increment the token ID for the next mint
    }

    // Repair function: allows NFT owners to repair their NFTs using a repair potion
    function repair(uint256 tokenId) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(IERC20(potionToken).balanceOf(msg.sender) >= 1, "Insufficient repair potions");
        require(health[tokenId] < 255, "NFT is already at full health");
        // Use the consume function of the repair potion contract to burn one repair potion
        RepairPotion(potionToken).consume(tokenId);
        health[tokenId] += 1;
        emit TokenRepaired(msg.sender, tokenId);
    }

    function hasSufficientBalance(uint256 amount) public view returns (bool) {
        uint256 balance = rewardToken == address(0) ? address(this).balance : IERC20(rewardToken).balanceOf(address(this));
        return balance >= amount;
    }

    // Claim reward function for NFT holders. Make sure to use reentrancy guard
    function claim(uint256 tokenId) public nonReentrant {
        // Protect users from claiming when the contract doesn't have enough funds
        require(hasSufficientBalance(rewardRate), "Insufficient funds for rewards");
        // In the rare case where the special reward rate is more than the reward rate, which could happen? 
        require(hasSufficientBalance(specialRewardRate), "Insufficient funds for special rewards");
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(!hasClaimedInPeriod[tokenId], "Already claimed this period");
        // The claim liimt is enforced until the period ends, preventing any more claimers. Then when the claim period is over, whoever tries to claim gets the special reward fund.
        require(totalClaims[tokenId] <= claimerLimit || isClaimReady(), "Claimer limit reached");

        require(health[tokenId] > min_health, "NFT is too damaged");
        health[tokenId] -= 1;
        totalClaims[tokenId] += 1;
    

        // If the period has not ended, register the claimant. Otherwise, the reward is distributed and instead the person trying to claim gets a special reward which is a thank you for covering the gas fees for the finalization process.
        if (!_checkAndFinalizePeriod()) {
            claimants.push(Claimant(msg.sender, tokenId));
            hasClaimedInPeriod[tokenId] = true;
        } else {
            _distributeReward(msg.sender, tokenId, specialRewardRate);
        }
        emit RewardClaimed(msg.sender, tokenId);
    }

    // External view check if past the claim period
    function isClaimReady() public view returns (bool) {
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
        if (claimants.length == 0) {
            return 0;
        }
        return rewardRate / claimants.length;
    }
    
    // Check if it's time to finalize the current claim period
    function _checkAndFinalizePeriod() internal returns (bool) {
        if (block.timestamp > lastClaimTime + claimPeriod) {
            if (claimants.length >= min_claims) {
                uint256 reward = rewardRate / claimants.length;
                
                for (uint256 i = 0; i < claimants.length; i++) { 
                    Claimant memory claimant = claimants[i];
                    address addr = claimant.addr;
                    uint256 tokenId = claimant.tokenId;
                    _distributeReward(addr, tokenId, reward);
                    hasClaimedInPeriod[tokenId] = false;
                }
                lastClaimTime = block.timestamp;
                delete claimants;        
                return true;
            } else {
                // If there are not enough claimants just scratch the whole period.
                delete claimants;
                lastClaimTime = block.timestamp;
                return false;
            }
        }
        return false;
    }
        
    function _distributeReward(address claimant, uint256 tokenId, uint256 reward) internal {
        require(hasSufficientBalance(reward), "Insufficient funds for rewards");
        if (rewardToken == address(0)) {
            (bool success, ) = payable(claimant).call{value: reward}("");
            require(success, "Native token transfer failed");
        } else {
            require(IERC20(rewardToken).transfer(claimant, reward), "ERC20 transfer failed");
        }
        emit RewardDistributed(claimant, tokenId, reward);
    }    

    // Function to override tokenURI, fetching the metadata from the base URL
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Non-existent token");
        return string(abi.encodePacked(_baseTokenURI, Strings.toString(tokenId)));
    }

    // Owner can set the base token URI for metadata
    function setBaseTokenURI(string memory baseTokenURI) public onlyOwner {
        _baseTokenURI = baseTokenURI;
    }

    // Owner can set the payment token and price
    function setPaymentToken(address _paymentToken) public onlyOwner {
        require(_paymentToken == address(0) || IERC20(_paymentToken).totalSupply() > 0, "Invalid payment token");
        paymentToken = _paymentToken;
    }

    // Owner can set price for minting
    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
    }

    // Owner can set the reward token and rate
    function setRewardToken(address _rewardToken) public onlyOwner {
        require(_rewardToken == address(0) || IERC20(_rewardToken).totalSupply() > 0, "Invalid reward token");
        rewardToken = _rewardToken;
    }

    // Owner can set the reward rate
    function setRewardRate(uint256 _rewardRate) public onlyOwner {
        rewardRate = _rewardRate;
    }
    
    // Owner can set the special reward rate
    function setSpecialRewardRate(uint256 _specialRewardRate) public onlyOwner {
        specialRewardRate = _specialRewardRate;
    }

    // Owner can set the claim period
    function setClaimPeriod(uint256 _claimPeriod) public onlyOwner {
        claimPeriod = _claimPeriod;
    }

    // Owner can set the minimum number of claims required to finalize a period
    function setMinClaims(uint256 _min_claims) public onlyOwner {
        require(_min_claims > 0, "Minimum claims must be greater than zero");
        min_claims = _min_claims;
    }

    // Owner can set the minimum health required to claim rewards
    function setMinHealth(uint8 _min_health) public onlyOwner {
        min_health = _min_health;
    }

    // Override required for Solidity (for ERC721Enumerable)
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // Override required for Solidity (for ERC721Enumerable)
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}