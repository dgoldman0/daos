// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Summary: This contract is a simple implementation of a reward pool NFT that allows users to mint NFTs and claim rewards. The contract has a claim period, and rewards are distributed to NFT holders at the end of each period. The contract can be used with either native tokens or ERC-20 tokens for minting and rewards. The contract also allows the owner to set the payment token, price, and reward rate.

import "@openzeppelin/contracts@4.9.0/token/ERC721/IERC721.sol";
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
        require(RewardPoolNFT(_poolContract).isRewardPoolNFT(), "Invalid controller contract");
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
        address _tokenOwner = IERC721(poolContract).ownerOf(tokenId);        
        require(balanceOf(_tokenOwner) >= 1, "Insufficient repair potions");
        _burn(_tokenOwner, 1);
    }
}

// Some of stuff from payment should be in claim manager I think...
contract ClaimManager is Ownable {
    mapping (address => bool) public controllers; // Only the controller contract can modify data

    struct NFTInfo {
        uint256 totalClaims;
        bool hasClaimedInPeriod;
        uint8 health;
    }

    struct Claimant {
        address addr;
        uint256 tokenId;
    }

    Claimant[] public claimants;

    address public nftContract;
    address public paymentManager;

    uint256 public claimerLimit; // Maximum number of claimants in a period
    uint256 public claimPeriod;
    uint8 public min_health = 128; // Minimum token health required to claim rewards

    event Claim(address indexed claimant, uint256 indexed tokenId);

    constructor(address _nftContract, uint256 _claimerLimit, uint256 _claimPeriod, uint8 _min_health) Ownable() {
        nftContract = _nftContract;
        claimerLimit = _claimerLimit;
        claimPeriod = _claimPeriod;
        min_health = _min_health;
    }

    // Mapping to store claim information for each NFT tokenId
    mapping(uint256 => NFTInfo) private claimData;

    // Function to initialize claim data for a new NFT (only controller can call this)
    function initializeNFT(uint256 tokenId) external {
        require(msg.sender == address(nftContract), "Only the NFT contract can call this function");
        claimData[tokenId] = NFTInfo(0, false, 255); // default full health
    }

    // Function to check if the tokenId has claimed in the current period
    function hasClaimedInPeriod(uint256 tokenId) external view returns (bool) {
        return claimData[tokenId].hasClaimedInPeriod;
    }

    // Function to get the health of an NFT
    function getHealth(uint256 tokenId) external view returns (uint8) {
        return claimData[tokenId].health;
    }

    function getTotalClaims(uint256 tokenId) external view returns (uint256) {
        return claimData[tokenId].totalClaims;
    }

    function isClaimReady() public view returns (bool) {
        return block.timestamp > PaymentManager(paymentManager).lastClaimTime() + claimPeriod;
    }

    function resetClaim(uint256 tokenId) external 
    {  
        require(msg.sender == paymentManager, "Only the payment manager can call this function");
        claimData[tokenId].hasClaimedInPeriod = false;
    }

    // Really should change the name from "claim" to something else...
    function claim(uint256 tokenId) public {
        // Protect users from claiming when the contract doesn't have enough funds
        PaymentManager _paymentManager = PaymentManager(paymentManager);
        require(_paymentManager.hasSufficientBalance(_paymentManager.rewardRate()), "Insufficient funds for rewards");
        // In the rare case where the special reward rate is more than the reward rate, which could happen? 
        require(_paymentManager.hasSufficientBalance(_paymentManager.specialRewardRate()), "Insufficient funds for special rewards");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(!claimData[tokenId].hasClaimedInPeriod, "Already claimed this period");
        // The claim liimt is enforced until the period ends, preventing any more claimers. Then when the claim period is over, whoever tries to claim gets the special reward fund.
        require(claimants.length <= claimerLimit || isClaimReady(), "Claimer limit reached");

        require(claimData[tokenId].health >= min_health, "NFT health is too low to claim rewards");
    
        // If the period has not ended, register the claimant. Otherwise, the reward is distributed and instead the person trying to claim gets a special reward which is a thank you for covering the gas fees for the finalization process.
        if (_paymentManager.checkAndFinalizePeriod()) {
            _paymentManager.distributeReward(msg.sender, tokenId, _paymentManager.specialRewardRate());
        }

        claimData[tokenId].totalClaims += 1;
        claimData[tokenId].hasClaimedInPeriod = true;
        claimData[tokenId].health -= 1;
        // Add the claimant to the list of claimants
        address addr = IERC721(nftContract).ownerOf(tokenId);
        claimants.push(Claimant(addr, tokenId));
        emit Claim(addr, tokenId);
    }
    
    function getClaimantsCount() external view returns (uint256) {
        return claimants.length;
    }

    function getClaimants() external view returns (Claimant[] memory) {
        return claimants;
    }

    function claimant(uint256 index) external view returns (Claimant memory) {
        return claimants[index];
    }

    function deleteClaimants() external {
        require(msg.sender == address(paymentManager), "Only the payment manager can call this function");
        delete claimants;
    }

    // Function to repair an NFT's health (only controller can call this)
    function repairHealth(uint256 tokenId, uint8 repairAmount) external {
        require(msg.sender == address(nftContract), "Only the NFT contract can call this function");
        require(claimData[tokenId].health < 255, "NFT health is already full");
        claimData[tokenId].health += repairAmount;
        if (claimData[tokenId].health > 255) {
            claimData[tokenId].health = 255; // Ensure health doesn't exceed max value
        }
    }

    // Owner can set the minimum health required to claim rewards
    function setMinHealth(uint8 _min_health) public onlyOwner {
        min_health = _min_health;
    }

    // Owner can set the claim period
    function setClaimPeriod(uint256 _claimPeriod) public onlyOwner {
        claimPeriod = _claimPeriod;
    }

    // Owner can set the claimer limit
    function setClaimerLimit(uint256 _claimerLimit) public onlyOwner {
        claimerLimit = _claimerLimit;
    }

    // Owner can set the NFT contract
    function setNFTContract(address _nftContract) public onlyOwner {
        nftContract = _nftContract;
    }

    // Owner can set payment manager
    function setPaymentManager(address _paymentManager) public onlyOwner {
        paymentManager = _paymentManager;
    }
}

// Payout Manager: This is the contract that needs to be kept full to ensure claims.
contract PaymentManager is Ownable {
    uint256 public lastClaimTime;
    uint256 public rewardRate; // r - daily prize amount
    uint256 public specialRewardRate; // s - special prize amount
    uint256 public min_claims; // Minimum number of claims required to finalize a period
    
    address public rewardToken;

    address public claimManager;
    address public nftContract;

    event RewardDistributed(address indexed claimant, uint256 indexed tokenId, uint256 amount);

    constructor(address _nftContract, address _rewardToken, uint256 _rewardRate, uint256 _specialRewardRate, uint256 _min_claims) Ownable() {
        nftContract = _nftContract;
        rewardToken = _rewardToken;
        rewardRate = _rewardRate;
        specialRewardRate = _specialRewardRate;
        min_claims = _min_claims;
        lastClaimTime = block.timestamp;
    }

    function hasSufficientBalance(uint256 amount) public view returns (bool) {
        uint256 balance = rewardToken == address(0) ? address(this).balance : IERC20(rewardToken).balanceOf(address(this));
        return balance >= amount;
    }

    // Check if it's time to finalize the current claim period
    function checkAndFinalizePeriod() external returns (bool) {
        require(msg.sender == claimManager, "Only the claim manager can call this function");
        ClaimManager _claimManager = ClaimManager(claimManager);
        if (block.timestamp > lastClaimTime + _claimManager.claimPeriod()) {
            uint256 len = _claimManager.getClaimantsCount();
            if (len >= min_claims) {
                uint256 reward = rewardRate / len;
                
                // Should transfer this to the payment manager
                for (uint256 i = 0; i < len; i++) { 
                    ClaimManager.Claimant memory claimant = _claimManager.claimant(i);
                    address addr = claimant.addr;
                    uint256 tokenId = claimant.tokenId;
                    _distributeReward(addr, tokenId, reward);
                    _claimManager.resetClaim(tokenId);
                }
                lastClaimTime = block.timestamp;
                _claimManager.deleteClaimants();
                return true;
            } else {
                // If there are not enough claimants just scratch the whole period.
                _claimManager.deleteClaimants();
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

    function distributeReward(address claimant, uint256 tokenId, uint256 reward) external {
        require(msg.sender == address(claimManager), "Only the claim manager can call this function");
        _distributeReward(claimant, tokenId, reward);
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

    // Owner can set the minimum number of claims required to finalize a period
    function setMinClaims(uint256 _min_claims) public onlyOwner {
        require(_min_claims > 0, "Minimum claims must be greater than zero");
        min_claims = _min_claims;
    }

    // Owner can set the nft contract
    function setNFTContract(address _nftContract) public onlyOwner {
        nftContract = _nftContract;
    }

    // Owner can set the claim manager contract
    function setClaimManager(address _claimManager) public onlyOwner {
        claimManager = _claimManager;
    }
}

// Gotta pull some more claim functionality out of the main contract and put it into the claim manager. Same with the payment manager. Actually haven't integrated payment manager really yet...
contract RewardPoolNFT is ERC721Enumerable, Ownable {
    address public potionToken;

   // Token information
    string private _baseTokenURI;
    address public paymentToken;
    address public claimManager;
    address public paymentManager;

    uint256 public nextTokenId; // Unique ID for minted NFTs

    uint256 public mintPrice; // Price to mint an NFT

    event NFTMinted(address indexed minter, uint256 indexed tokenId);
    event TokenRepaired(address indexed owner, uint256 indexed tokenId);

    constructor(address _potionContract) ERC721("Reward Pool NFT", "RPNFT") Ownable() {
        nextTokenId = 1; // Start token IDs from 1
        // Replace with initalize method
        potionToken = _potionContract;
        paymentToken = address(0);  
        mintPrice = 100000000000000000; // Default price is 0.1 ETH
        _baseTokenURI = "https://api.arcadium.fun/token/";
    }
    
    // Mint function: allows minting NFTs with either ERC-20 or native token
    function mint() public payable nonReentrant {
        if (paymentToken == address(0)) {
            require(msg.value >= mintPrice, "Insufficient native token amount");
            if (msg.value > mintPrice) {
                uint256 amt = msg.value - mintPrice;
                (bool success, ) = payable(msg.sender).call{value: amt}("");
                require(success, "Ether transfer failed");
            }
        } else {
            require(IERC20(paymentToken).transferFrom(msg.sender, address(this), mintPrice), "ERC-20 transfer failed");
        }
        
        // Mint the NFT to the sender with a unique tokenId
        _safeMint(msg.sender, nextTokenId);
        ClaimManager(claimManager).initializeNFT(nextTokenId);
        emit NFTMinted(msg.sender, nextTokenId);
        nextTokenId += 1; // Increment the token ID for the next mint
    }

    // Repair function: allows NFT owners to repair their NFTs using a repair potion
    function repair(uint256 tokenId) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(IERC20(potionToken).balanceOf(msg.sender) >= 1, "Insufficient repair potions");
        require(ClaimManager(claimManager).getHealth(tokenId) < 255, "NFT health is already full");
        // Use the consume function of the repair potion contract to burn one repair potion
        RepairPotion(potionToken).consume(tokenId);
        ClaimManager(claimManager).repairHealth(tokenId, 1);
        emit TokenRepaired(msg.sender, tokenId);
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
        mintPrice = _price;
    }

    // Owner can set the repair potion token
    function setPotionToken(address _potionToken) public onlyOwner {
        potionToken = _potionToken;
    }

    // Owner can set the data manager contract
    function setClaimManager(address _claimManager) public onlyOwner {
        claimManager = _claimManager;
    }

    // Owner can set the payment manager contract
    function setPaymentManager(address _paymentManager) public onlyOwner {
        paymentManager = _paymentManager;
    }

    // Override required for Solidity (for ERC721Enumerable)
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function isRewardPoolNFT() external pure returns (bool) {
        return true;
    }
}