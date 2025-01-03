// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// System of contracts that managers an NFT based reward pool. It consists of a custom Ownable contract, which allows for ownership transfer and fund withdrawal, a RepairPotion contract, which is an ERC20 token used to repair NFTs, two manager contracts which manage extended NFT information and claiming, and payouts respectively, and a RewardPoolNFT contract, which is an ERC721 NFT contract that mints NFTs for the reward pool, and allows owner to set price of mint.

import "@openzeppelin/contracts@4.9.0/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.0/utils/Strings.sol";
import "./utils/ownable.sol";

// Repair potions are ERC20 tokens that can be used to repair NFTs: Should I allow anyone to mint for a fee like with the NFTs? Not sure.
contract RepairPotion is ERC20, Ownable {
    address public managerContract;
    address payable public fundReceiver;
    address public purchaseToken;
    uint256 public purchasePrice;
    uint256 public maxSupply;

    constructor(uint256 _maxSupply, address _purchaseToken, uint256 _purchasePrice) ERC20("Repair Potion", "REPOT") {
        maxSupply = _maxSupply;
        purchaseToken = _purchaseToken;
        purchasePrice = _purchasePrice;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return 0;
    }

    function buy(uint256 amount) public payable nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(amount + totalSupply() <= maxSupply, "Exceeds maximum supply");
        uint256 cost = purchasePrice * amount;
        require((purchaseToken == address(0) && msg.value == cost) || IERC20(purchaseToken).balanceOf(msg.sender) >= cost && IERC20(purchaseToken).allowance(msg.sender, address(this)) >= cost, "Insufficient funds or allowance");
        require(purchaseToken == address(0) || msg.value == 0, "ETH payment not allowed");
        IERC20(purchaseToken).transferFrom(msg.sender, address(this), cost);

        if (purchaseToken == address(0)) {
            // Refund any excess payment
            if (msg.value > cost) {
                payable(msg.sender).transfer(msg.value - cost);
            }
        }
        _mint(msg.sender, amount);

        // Transfer the purchase amount to the fund receiver if set
        if (address(fundReceiver) != address(0) && Ownable(fundReceiver).owner() != address(0)) {
            if (purchaseToken == address(0)) {
                fundReceiver.transfer(cost);
            } else {
                IERC20(purchaseToken).transfer(fundReceiver, cost);
            }
        }
    }

    // Consume a potion
    function consume(address _tokenOwner) public {
        require(msg.sender == managerContract, "Only the pool contract can repair NFTs");
        require(balanceOf(_tokenOwner) >= 1, "Insufficient repair potions");
        _burn(_tokenOwner, 1);
    }

    function setManagerContract(address _managerContract) public onlyOwner {
        managerContract = _managerContract;
    }

    function setPurchaseToken(address _purchaseToken) public onlyOwner {
        require(_purchaseToken == address(0) || IERC20(_purchaseToken).totalSupply() > 0, "Invalid purchase token");
        purchaseToken = _purchaseToken;
    }

    function setPurchasePrice(uint256 _purchasePrice) public onlyOwner {
        purchasePrice = _purchasePrice;
    }

    function setMaxSupply(uint256 _maxSupply) public onlyOwner {
        require(_maxSupply >= totalSupply(), "New max supply must be greater than the current supply");
        maxSupply = _maxSupply;
    }

    function setFundReceiver(address payable _fundReceiver) public onlyOwner {
        fundReceiver = _fundReceiver;
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
        ClaimNFTManager _claimManager = ClaimNFTManager(payable(claimManager));
        if (block.timestamp > lastClaimTime + _claimManager.claimPeriod()) {
            uint256 len = _claimManager.getClaimantsCount();
            if (len >= min_claims) {
                uint256 reward = rewardRate / len;
                
                // Should transfer this to the payment manager
                for (uint256 i = 0; i < len; i++) { 
                    ClaimNFTManager.Claimant memory claimant = _claimManager.claimant(i);
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
                for (uint256 i = 0; i < len; i++) {
                    ClaimNFTManager.Claimant memory claimant = _claimManager.claimant(i);
                    _claimManager.resetClaim(claimant.tokenId);
                }
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

// Should really extract extract the data to yet another contract now and turn this into the claim contract controller
// Handles NFT detials and claims... 
contract ClaimNFTManager is Ownable {
    mapping (address => bool) public controllers;

    // Would just be another controller in the new system which means that potions also need to be extracted out
    address public potionToken; 

    struct NFTInfo {
        uint256 mintDate;
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
    event TokenRepaired(address indexed owner, uint256 indexed tokenId, uint256 qnt);

    constructor(address _nftContract, address _potionToken, address _paymentManager, uint256 _claimerLimit, uint256 _claimPeriod, uint8 _min_health) Ownable() {
        nftContract = _nftContract;
        potionToken = _potionToken;
        paymentManager = _paymentManager;
        claimerLimit = _claimerLimit;
        claimPeriod = _claimPeriod;
        min_health = _min_health;
    }

    // Mapping to store claim information for each NFT tokenId
    mapping(uint256 => NFTInfo) private claimData;

    // Function to initialize claim data for a new NFT (only controller can call this)
    function initializeNFT(uint256 tokenId) external {
        require(msg.sender == nftContract, "Only the NFT contract can call this function");
        claimData[tokenId] = NFTInfo(block.timestamp, 0, false, 255);
    }

    // Function to check if the tokenId has claimed in the current period
    function hasClaimedInPeriod(uint256 tokenId) external view returns (bool) {
        require(claimData[tokenId].mintDate > 0, "NFT not initialized");
        return claimData[tokenId].hasClaimedInPeriod;
    }

    // Function to get the health of an NFT
    function getHealth(uint256 tokenId) external view returns (uint8) {
        require(claimData[tokenId].mintDate > 0, "NFT not initialized");
        return claimData[tokenId].health;
    }

    function getMintDate(uint256 tokenId) external view returns (uint256) {
        return claimData[tokenId].mintDate;
    }

    function getTotalClaims(uint256 tokenId) external view returns (uint256) {
        require(claimData[tokenId].mintDate > 0, "NFT not initialized");
        return claimData[tokenId].totalClaims;
    }

    function isClaimReady() public view returns (bool) {
        return block.timestamp > PaymentManager(payable(paymentManager)).lastClaimTime() + claimPeriod;
    }

    function resetClaim(uint256 tokenId) external 
    {  
        require(msg.sender == paymentManager, "Only the payment manager can call this function");
        claimData[tokenId].hasClaimedInPeriod = false;
    }

    function claim(uint256 tokenId) public nonReentrant {
        // Protect users from claiming when the contract doesn't have enough funds
        PaymentManager _paymentManager = PaymentManager(payable(paymentManager));
        require(_paymentManager.hasSufficientBalance(_paymentManager.rewardRate()), "Insufficient funds for rewards");
        // In the rare case where the special reward rate is more than the reward rate, which could happen? 
        require(_paymentManager.hasSufficientBalance(_paymentManager.specialRewardRate()), "Insufficient funds for special rewards");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(!claimData[tokenId].hasClaimedInPeriod, "Already claimed this period");
        // The claim liimt is enforced until the period ends, preventing any more claimers. Then when the claim period is over, whoever tries to claim gets the special reward fund.
        require(claimants.length <= claimerLimit || isClaimReady(), "Claimer limit reached");

        require(claimData[tokenId].health >= min_health, "NFT health is too low to claim rewards");

        // Ensure there's enoguh funds in the payment manager to pay out rewards
        uint256 totalreward = _paymentManager.rewardRate() + _paymentManager.specialRewardRate();
        require(_paymentManager.hasSufficientBalance(totalreward), "Insufficient funds for rewards");
    
        // If the period has not ended, register the claimant. Otherwise, the reward is distributed and instead the person trying to claim gets a special reward which is a thank you for covering the gas fees for the finalization process.
        if (_paymentManager.checkAndFinalizePeriod()) {
            _paymentManager.distributeReward(msg.sender, tokenId, _paymentManager.specialRewardRate());
        }

        // Add the claimant to the list of claimants
        address addr = IERC721(nftContract).ownerOf(tokenId);
        claimData[tokenId].hasClaimedInPeriod = true;
        claimData[tokenId].totalClaims += 1;
        claimData[tokenId].health -= 1;
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
        require(msg.sender == paymentManager, "Only the payment manager can call this function");
        delete claimants;
    }

    // Repair function: allows NFT owners to repair their NFTs using a repair potion
    function repair(uint256 tokenId, uint8 _qnt) public nonReentrant {
        require(ERC721Enumerable(nftContract).ownerOf(tokenId) == msg.sender, "Not the owner of this NFT");
        require(IERC20(potionToken).balanceOf(msg.sender) >= _qnt, "Insufficient repair potions");
        require(claimData[tokenId].health + _qnt <= 255, "NFT health would be over limit");
        // Use the consume function of the repair potion contract to burn one repair potion
        for (uint8 i = 0; i < _qnt; i++) {
            RepairPotion(payable(potionToken)).consume(msg.sender);
        }
        claimData[tokenId].health += uint8(_qnt);
        emit TokenRepaired(msg.sender, tokenId, _qnt);
    }

    /* This stuff should be in a new data manager contract so this can be turned into the claim manager exclusive controller, but eh. */
    function addController(address _controller) public onlyOwner {
        controllers[_controller] = true;
    }

    function removeController(address _controller) public onlyOwner {
        controllers[_controller] = false;
    }

    function reduceHealth(uint256 tokenId, uint8 _qnt) public {
        require(controllers[msg.sender], "Only controllers can call this function");
        require(claimData[tokenId].mintDate > 0, "NFT not initialized");
        require(claimData[tokenId].health >= _qnt, "NFT health would be under limit");
        claimData[tokenId].health -= _qnt;
    }

    function increaseHealth(uint256 tokenId, uint8 _qnt) public {
        require(controllers[msg.sender], "Only controllers can call this function");
        require(claimData[tokenId].mintDate > 0, "NFT not initialized");
        require(claimData[tokenId].health + _qnt <= 255, "NFT health would be over limit");
        claimData[tokenId].health += _qnt;
    }

    /* End part that should be in its own data manager contract */

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

    // Owner can set the repair potion token
    function setPotionToken(address _potionToken) public onlyOwner {
        potionToken = _potionToken;
    }
}

// Maybe before live version pull the repair method out of this contract...
contract RewardPoolNFT is ERC721Enumerable, Ownable {
   // Token information
    string private _baseTokenURI;
    address public paymentToken;
    address public claimManager;
    address payable public fundReceiver;

    uint256 public nextTokenId; // Unique ID for minted NFTs

    uint256 public mintPrice; // Price to mint an NFT
    uint256 public maxSupply = 10000; // Maximum supply of NFTs

    uint256 public firstMintDate;

    event NFTMinted(address indexed minter, uint256 indexed tokenId);

    constructor() ERC721("Reward Pool NFT", "RPNFT") Ownable() {
        nextTokenId = 1;
        // Replace with initalize method
        paymentToken = address(0);  
        mintPrice = 10000000000000000; // Default price is 0.01 ETH
        _baseTokenURI = "https://api.arcadium.fun/token/";
    }
    
    // Mint function: allows minting NFTs with either ERC-20 or native token
    function mint(uint256 _count) public payable nonReentrant {
        require(_count > 0, "Count must be greater than zero");
        require(nextTokenId + _count <= maxSupply, "Exceeds maximum supply");
        uint256 totalMintPrice = mintPrice * _count;
        if (paymentToken == address(0)) {
            require(msg.value >= totalMintPrice, "Insufficient native token amount");
            if (msg.value > totalMintPrice) {
                payable(msg.sender).transfer(msg.value - totalMintPrice);
            }
        } else {
            require(IERC20(paymentToken).transferFrom(msg.sender, address(this), totalMintPrice), "ERC-20 transfer failed");
        }

        if (firstMintDate == 0) {
            firstMintDate = block.timestamp;
        }

        for (uint256 i = 0; i < _count; i++) {
            // Placing the emit here ensures that the minted event is broadcast before the transfer event is broadcast.
            emit NFTMinted(msg.sender, nextTokenId);
            _safeMint(msg.sender, nextTokenId);
            ClaimNFTManager(payable(claimManager)).initializeNFT(nextTokenId);
            nextTokenId += 1;
        }

        // Transfer the mint fee to the fund receiver if set
        if (address(fundReceiver) != address(0) && Ownable(fundReceiver).owner() != address(0)) {
            if (paymentToken == address(0)) {
                fundReceiver.transfer(totalMintPrice);
            } else {
                IERC20(paymentToken).transfer(fundReceiver, totalMintPrice);
            }
        }
    }

    function mintTo(address _to, uint256 _count) public onlyOwner nonReentrant {
        if (firstMintDate == 0) {
            firstMintDate = block.timestamp;
        }
        for (uint256 i = 0; i < _count; i++) {
            _safeMint(_to, nextTokenId);
            ClaimNFTManager(payable(claimManager)).initializeNFT(nextTokenId);
            nextTokenId += 1;
        }
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

    // Owner can set the maximum supply of NFTs
    function setMaxSupply(uint256 _maxSupply) public onlyOwner {
        require(_maxSupply >= nextTokenId, "New max supply must be greater than the next token ID");
        maxSupply = _maxSupply;
    }
    
    // Owner can set the data manager contract
    function setClaimManager(address _claimManager) public onlyOwner {
        claimManager = _claimManager;
    }

    // Override required for Solidity (for ERC721Enumerable)
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Owner can set the fund receiver
    function setFundReceiver(address payable _fundReceiver) public onlyOwner {
        fundReceiver = _fundReceiver;
    }
}