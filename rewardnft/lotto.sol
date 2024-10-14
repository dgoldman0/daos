// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/irandomseedgenerator.sol";
import "./utils/ownable.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/IERC20.sol";

contract LottoMachine is Ownable {
    address public randomseedgenerator;
    address public rewardToken;
    uint256 public prizeAmount;
    uint256 public prizePermyriad; // Used of prizeAmount = 0
    address public feeToken;
    uint256 public feeAmount;
    uint128 public odds; 

    // Events
    event Play(address indexed player, uint256 seed, uint256 random, bool win, uint256 prize);

    constructor(address _randomseedgenerator) Ownable() {
        randomseedgenerator = _randomseedgenerator;
    }

    function play() public payable returns (uint256) {
        // If contract is 0 then it's ETH, otherwise ERC20
        require((feeToken == address(0) && msg.value >= feeAmount) || IERC20(feeToken).balanceOf(msg.sender) >= feeAmount, "No funds sent");
        
        require(odds > 0, "Odds not set");
        require(prizeAmount > 0 || prizePermyriad > 0, "No reward set");

        uint256 actualPrize = getPrizeAmount();

        // Ensure balance is enough
        require(feeToken == address(0) ? address(this).balance >= actualPrize : IERC20(feeToken).balanceOf(address(this)) >= actualPrize, "Insufficient funds");

        // Refund excess if there is any
        if (feeToken == address(0) && msg.value > feeAmount) {
            payable(msg.sender).transfer(msg.value - feeAmount);
        } else if (feeToken != address(0) && IERC20(feeToken).balanceOf(msg.sender) > feeAmount) {
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
            emit Play(msg.sender, seed, random, true, actualPrize);
        } else {
            emit Play(msg.sender, seed, random, false, 0);
        }

    }

    function getPrizeAmount() public view returns (uint256) {
        if (prizeAmount == 0) {
            uint256 bal = feeToken == address(0) ? address(this).balance : IERC20(feeToken).balanceOf(address(this));
            return (bal * prizePermyriad) / 10000;
        }
        return prizeAmount;
    }
    
    function setRandomSeedGenerator(address _randomseedgenerator) external onlyOwner {
        randomseedgenerator = _randomseedgenerator;
    }

    function setOdds(uint128 _odds) external onlyOwner {
        odds = _odds;
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
}