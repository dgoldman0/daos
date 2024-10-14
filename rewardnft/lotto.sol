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

    constructor(address _randomseedgenerator) Ownable() {
        randomseedgenerator = _randomseedgenerator;
    }

    function play() public payable returns (uint256) {
        // If contract is 0 then it's ETH, otherwise ERC20
        require((feeToken == address(0) && msg.value >= feeAmount) || IERC20(feeToken).balanceOf(msg.sender) >= feeAmount, "No funds sent");
        // Refund excess if there is any
        if (feeToken == address(0) && msg.value > feeAmount) {
            payable(msg.sender).transfer(msg.value - feeAmount);
        } else if (feeToken != address(0) && IERC20(feeToken).balanceOf(msg.sender) > feeAmount) {
            IERC20(feeToken).transferFrom(msg.sender, address(this), feeAmount);
        }
        uint256 seed = IRandomSeedGenerator(randomseedgenerator).getSeed();
        uint256 random = uint256(keccak256(abi.encodePacked(seed, block.timestamp, msg.sender))) % odds;
        if (random == 0) {
            uint256 amt = prizeAmount;
            if (prizeAmount == 0) {
                amt = (feeAmount * prizePermyriad) / 10000;
            }
            if (rewardToken == address(0)) {
                payable(msg.sender).transfer(amt);
            } else {
                IERC20(rewardToken).transfer(msg.sender, amt);
            }
        }
    }

    function setRandomSeedGenerator(address _randomseedgenerator) external onlyOwner {
        randomseedgenerator = _randomseedgenerator;
    }

    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = _rewardToken;
    }

    function setPrizeAmount(uint256 _prizeAmount) external onlyOwner {
        prizeAmount = _prizeAmount;
    }

    function setOdds(uint128 _odds) external onlyOwner {
        odds = _odds;
    }
}