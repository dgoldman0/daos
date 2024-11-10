// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/irandomseedgenerator.sol";
import "./utils/ownable.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./iclaimnftmanager.sol";

// Still a lot of work to do, gotta add minimum age, etc. 
contract LottoMachine is Ownable {
    address public randomseedgenerator;
    address public rewardToken;
    uint256 public prizeAmount;
    uint256 public prizePermyriad; // Used of prizeAmount = 0
    address public feeToken;
    uint256 public feeAmount;
    uint128 public odds; 
    uint256 public cooldownPeriod; // Cooldown period for NFTs

    address keyNFTContract;
    address keyDataManager;

    // Minimum health of the key
    uint256 public minKeyHealth;
    // Minimum age of the key
    uint256 public minKeyAge;
    // Minimum number of claims
    uint256 public minKeyClaims;    

    mapping (uint256 => uint256) public lastPlayed; // Record of when the NFT last used to play

    // Events
    event Play(address indexed player, uint256 indexed key, uint256 seed, uint256 random, bool win, uint256 prize);

    constructor() Ownable() {
    }

    function play(uint256 _key) public payable returns (uint256 _prize) {
        // If contract is 0 then it's ETH, otherwise ERC20
        require((feeToken == address(0) && msg.value >= feeAmount) || IERC20(feeToken).balanceOf(msg.sender) >= feeAmount, "No funds sent");
        
        require(odds > 0, "Odds not set");
        require(prizeAmount > 0 || prizePermyriad > 0, "No reward set");

        uint256 actualPrize = getPrizeAmount();

        // Ensure balance is enough
        require(rewardToken == address(0) ? address(this).balance >= actualPrize : IERC20(rewardToken).balanceOf(address(this)) >= actualPrize, "Insufficient funds");

        // Check if the key is valid
        require(IERC721(keyNFTContract).ownerOf(_key) == msg.sender, "Not the owner of the key");
        require(IClaimNFTManager(keyDataManager).getHealth(_key) >= minKeyHealth, "Key health too low");
        require(block.timestamp - IClaimNFTManager(keyDataManager).getMintDate(_key) >= minKeyAge, "Key age too low");
        require(IClaimNFTManager(keyDataManager).getTotalClaims(_key) >= minKeyClaims, "Key claims too low");
        require(block.timestamp - lastPlayed[_key] >= cooldownPeriod, "Key on cooldown");

        lastPlayed[_key] = block.timestamp;

        // Refund excess if there is any
        if (feeToken != address(0) && IERC20(feeToken).balanceOf(msg.sender) > feeAmount) {
            IERC20(feeToken).transferFrom(msg.sender, address(this), feeAmount);
        }

        uint256 seed = IRandomSeedGenerator(randomseedgenerator).getSeed();
        uint256 random = uint256(keccak256(abi.encodePacked(seed, block.timestamp, msg.sender))) % odds;
        if (random == 0) {
            if (rewardToken == address(0)) {
                payable(msg.sender).transfer(actualPrize);
            } else {
                IERC20(rewardToken).transfer(msg.sender, actualPrize);
            }
            emit Play(msg.sender, _key, seed, random, true, actualPrize);
            return actualPrize;
        } else {
            emit Play(msg.sender, _key, seed, random, false, 0);
            return 0;
        }
    }

    function getPrizeAmount() public view returns (uint256) {
        if (prizeAmount == 0) {
            uint256 bal = rewardToken == address(0) ? address(this).balance : IERC20(rewardToken).balanceOf(address(this));
            return (bal * prizePermyriad) / 10000;
        }
        return prizeAmount;
    }

    // Check if the key is eligible to play
    function isKeyEligible(uint256 _key) public view returns (bool) {
        if (IERC721(keyNFTContract).ownerOf(_key) != msg.sender) {
            return false;
        }
        if (IClaimNFTManager(keyDataManager).getHealth(_key) < minKeyHealth) {
            return false;
        }
        if (block.timestamp - IClaimNFTManager(keyDataManager).getMintDate(_key) < minKeyAge) {
            return false;
        }
        if (IClaimNFTManager(keyDataManager).getTotalClaims(_key) < minKeyClaims) {
            return false;
        }
        if (block.timestamp - lastPlayed[_key] < cooldownPeriod) {
            return false;
        }
        return true;
    }
    
    function setRandomSeedGenerator(address _randomseedgenerator) external onlyOwner {
        randomseedgenerator = _randomseedgenerator;
    }

    function setOdds(uint128 _odds) external onlyOwner {
        odds = _odds;
    }

    function setMinKeyHealth(uint256 _minKeyHealth) external onlyOwner {
        minKeyHealth = _minKeyHealth;
    }

    function setMinKeyAge(uint256 _minKeyAge) external onlyOwner {
        minKeyAge = _minKeyAge;
    }

    function setMinKeyClaims(uint256 _minKeyClaims) external onlyOwner {
        minKeyClaims = _minKeyClaims;
    }

    function setCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        cooldownPeriod = _cooldownPeriod;
    }

    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = _rewardToken;
    }

    function setPrizeAmount(uint256 _prizeAmount) external onlyOwner {
        require(prizePermyriad == 0 || _prizeAmount == 0, "Prize permyriad is set");
        prizeAmount = _prizeAmount;
    }

    function setPrizePermyriad(uint256 _prizePermyriad) external onlyOwner {
        require(prizeAmount == 0 || _prizePermyriad == 0, "Prize amount is set");
        prizePermyriad = _prizePermyriad;
    }

    function setFeeToken(address _feeToken) external onlyOwner {
        feeToken = _feeToken;
    }

    function setFeeAmount(uint256 _feeAmount) external onlyOwner {
        feeAmount = _feeAmount;
    }

    function setKeyNFTContract(address _keyNFTContract) external onlyOwner {
        keyNFTContract = _keyNFTContract;
    }

    function setKeyDataManager(address _keyDataManager) external onlyOwner {
        keyDataManager = _keyDataManager;
    }
}