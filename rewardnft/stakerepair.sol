// Early draft
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IClaimNFTManager {
    function increaseHealth(uint256 tokenId, uint8 healthUnits) external;
}

contract StakingContract is ReentrancyGuard, Ownable {
    IERC20 public stakingToken;
    IClaimNFTManager public claimManager;
    IERC721 public nftContract;

    uint256 public repairRate; // Repair points per token per second
    uint256 public pointsPerHealthUnit; // Repair points required per unit of health restored

    bool public stakingEnabled = true;
    uint256 public totalStakers;
    uint256 public pauseTimestamp;

    struct StakeInfo {
        uint256 amount;
        uint256 lastUpdateTime;
        uint256 repairPoints;
        uint256 unstakeRequestedTime; // Time when unstake was requested
        uint256[4] withdrawableAmounts; // Four equal parts for withdrawal
    }

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed staker, uint256 amount);
    event Withdrawn(address indexed staker, uint256 amount);
    event RepairClaimed(address indexed staker, uint256 tokenId, uint256 healthRestored);
    event StakingStatusChanged(bool enabled);
    event RepairRateChanged(uint256 newRate);
    event PointsPerHealthUnitChanged(uint256 newPointsPerHealthUnit);
    event ForceUnstaked(address indexed staker, uint256 amount);
    event UnstakeRequested(address indexed staker, uint256 amount);

    constructor(
        address _stakingToken,
        address _claimManager,
        address _nftContract,
        uint256 _repairRate,
        uint256 _pointsPerHealthUnit
    ) {
        stakingToken = IERC20(_stakingToken);
        claimManager = IClaimNFTManager(_claimManager);
        nftContract = IERC721(_nftContract);
        repairRate = _repairRate;
        pointsPerHealthUnit = _pointsPerHealthUnit;
    }

    // Stake tokens
    function stake(uint256 amount) external nonReentrant {
        require(stakingEnabled, "Staking is currently disabled");
        require(amount > 0, "Cannot stake zero tokens");

        _updateRepairPoints(msg.sender);

        stakingToken.transferFrom(msg.sender, address(this), amount);

        if (stakes[msg.sender].amount == 0) {
            totalStakers += 1;
        }

        stakes[msg.sender].amount += amount;
        stakes[msg.sender].lastUpdateTime = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    // Request to unstake tokens (start cooldown period)
    function requestUnstake() external nonReentrant {
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.amount > 0, "No active stake found");
        require(stakeInfo.unstakeRequestedTime == 0, "Unstake already requested");

        _updateRepairPoints(msg.sender);

        stakeInfo.unstakeRequestedTime = block.timestamp;

        // Split the staked amount into four equal parts for withdrawal
        uint256 part = stakeInfo.amount / 4;
        stakeInfo.withdrawableAmounts = [part, part, part, part];

        emit UnstakeRequested(msg.sender, stakeInfo.amount);
    }

    // Withdraw staked tokens after the cooldown periods
    function withdraw() external nonReentrant {
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.amount > 0, "No active stake found");
        require(stakeInfo.unstakeRequestedTime > 0, "Unstake not requested");

        _updateRepairPoints(msg.sender);

        uint256 elapsedTime = block.timestamp - stakeInfo.unstakeRequestedTime;
        uint256 withdrawableAmount = 0;

        // Calculate how much can be withdrawn based on the elapsed time
        for (uint256 i = 0; i < 4; i++) {
            if (elapsedTime >= (i + 1) * 1 weeks && stakeInfo.withdrawableAmounts[i] > 0) {
                withdrawableAmount += stakeInfo.withdrawableAmounts[i];
                stakeInfo.withdrawableAmounts[i] = 0;
            }
        }

        require(withdrawableAmount > 0, "No tokens available for withdrawal yet");

        stakeInfo.amount -= withdrawableAmount;
        stakingToken.transfer(msg.sender, withdrawableAmount);

        // If fully withdrawn, delete the stake info and reduce the total staker count
        if (stakeInfo.amount == 0) {
            delete stakes[msg.sender];
            totalStakers -= 1;
        } else {
            stakeInfo.lastUpdateTime = block.timestamp;
        }

        emit Withdrawn(msg.sender, withdrawableAmount);
    }

    // Accumulate repair points based on staking duration and amount
    function _updateRepairPoints(address staker) internal {
        StakeInfo storage stakeInfo = stakes[staker];
        if (stakeInfo.amount > 0) {
            uint256 timeElapsed = block.timestamp - stakeInfo.lastUpdateTime;
            if (stakingEnabled) {
                uint256 additionalPoints = stakeInfo.amount * timeElapsed * repairRate;
                stakeInfo.repairPoints += additionalPoints;
            }
            stakeInfo.lastUpdateTime = block.timestamp;
        }
    }

    // Claim repair points to restore NFT health
    function claimRepair(uint256 tokenId, uint256 healthUnits) external nonReentrant {
        require(nftContract.ownerOf(tokenId) == msg.sender, "Caller does not own the NFT");

        _updateRepairPoints(msg.sender);

        StakeInfo storage stakeInfo = stakes[msg.sender];
        uint256 requiredPoints = healthUnits * pointsPerHealthUnit;
        require(stakeInfo.repairPoints >= requiredPoints, "Insufficient repair points");

        stakeInfo.repairPoints -= requiredPoints;

        // Use increaseHealth on the NFT via ClaimNFTManager
        claimManager.increaseHealth(tokenId, uint8(healthUnits));

        emit RepairClaimed(msg.sender, tokenId, healthUnits);
    }

    // Pause or resume staking
    function setStakingEnabled(bool _enabled) external onlyOwner {
        stakingEnabled = _enabled;
        if (!_enabled) {
            pauseTimestamp = block.timestamp;
        }
        emit StakingStatusChanged(_enabled);
    }

    // Set the repair rate (only when no active stakes and staking is paused)
    function setRepairRate(uint256 _repairRate) external onlyOwner {
        require(!stakingEnabled && totalStakers == 0, "Cannot change repair rate with active stakers or while staking enabled");
        repairRate = _repairRate;
        emit RepairRateChanged(_repairRate);
    }

    // Set points per health unit (only when no active stakes and staking is paused)
    function setPointsPerHealthUnit(uint256 _pointsPerHealthUnit) external onlyOwner {
        require(!stakingEnabled && totalStakers == 0, "Cannot change points per health unit with active stakers or while staking enabled");
        pointsPerHealthUnit = _pointsPerHealthUnit;
        emit PointsPerHealthUnitChanged(_pointsPerHealthUnit);
    }

    // Manual force unstake by the owner when staking is paused
    function forceUnstake(address staker) external onlyOwner nonReentrant {
        require(!stakingEnabled, "Staking must be paused to perform force unstake");

        StakeInfo storage stakeInfo = stakes[staker];
        require(stakeInfo.amount > 0, "No active stake for this address");

        // Calculate repair points up to the pause timestamp
        if (stakeInfo.lastUpdateTime <= pauseTimestamp) {
            uint256 timeElapsed = pauseTimestamp - stakeInfo.lastUpdateTime;
            uint256 additionalPoints = stakeInfo.amount * timeElapsed * repairRate;
            stakeInfo.repairPoints += additionalPoints;
        }

        uint256 amount = stakeInfo.amount;
        stakeInfo.amount = 0;
        totalStakers -= 1;

        stakingToken.transfer(staker, amount);

        emit ForceUnstaked(staker, amount);
    }
}
