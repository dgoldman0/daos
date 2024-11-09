// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./utils/ownable.sol";

// EnergyToken contract that can only be minted by the StakingContract
contract EnergyToken is ERC20, Ownable {
    address public stakingContract;

    constructor(address _stakingContract) ERC20("Energy", "ENG") {
        stakingContract = _stakingContract;
    }

    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "Not authorized to mint");
        _;
    }

    function mint(address to, uint256 amount) external onlyStakingContract {
        _mint(to, amount);
    }
}

contract StakingContract is ReentrancyGuard, Ownable {
    IERC20 public stakingToken;
    EnergyToken public energyToken;
    uint256 public energyRate; // Rate of energy generation per second

    struct StakeInfo {
        uint256 amount;            // Amount staked
        uint256 energyAccrued;     // Energy accumulated but not yet extracted
        uint256 lastUpdate;        // Last timestamp of energy accrual
        uint256 unstakeTime;       // Timestamp when unstake was initiated
        uint256 weeklyUnlock;      // Amount to unlock each week
        uint8 weeksCompleted;      // Number of weeks passed in the unstake process
        bool isUnstaking;          // Flag to check if unstaking is in process
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public totalStakers;
    bool public stakingEnabled;

    constructor(IERC20 _stakingToken, uint256 _energyRate) {
        stakingToken = _stakingToken;
        energyRate = _energyRate;
        stakingEnabled = false;
    }

    // Stake tokens
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(stakingEnabled, "Staking is currently disabled");
        bool alreadyStaking = stakes[msg.sender].amount > 0;
        stakingToken.transferFrom(msg.sender, address(this), amount);
        _updateEnergy(msg.sender);
        if (!alreadyStaking) {
            totalStakers++;
        }
        stakes[msg.sender].amount += amount;
        stakes[msg.sender].lastUpdate = block.timestamp;
    }

    // Extract energy
    function extractEnergy() external nonReentrant {
        _updateEnergy(msg.sender);
        uint256 energy = stakes[msg.sender].energyAccrued;
        require(energy > 0, "No energy to extract");
        stakes[msg.sender].energyAccrued = 0;
        energyToken.mint(msg.sender, energy);
    }

    // Initiate unstake process
    function initiateUnstake() external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        require(!userStake.isUnstaking, "Already unstaking");
        _updateEnergy(msg.sender);
        userStake.isUnstaking = true;
        userStake.unstakeTime = block.timestamp;
        userStake.weeklyUnlock = userStake.amount / 4;
        userStake.weeksCompleted = 0;
    }

    // Cancel unstake process
    function cancelUnstake() external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.isUnstaking, "Not unstaking");
        userStake.isUnstaking = false;
    }

    // Claim unlocked portion of staked tokens
    function claimUnlocked() external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.isUnstaking, "Not in unstake process");

        // Calculate weeks passed since unstake was initiated
        uint8 weeksPassed = uint8((block.timestamp - userStake.unstakeTime) / 1 weeks);
        require(weeksPassed > userStake.weeksCompleted, "No new unlocks");

        uint256 totalUnlocked = (weeksPassed - userStake.weeksCompleted) * userStake.weeklyUnlock;
        userStake.amount -= totalUnlocked;
        userStake.weeksCompleted = weeksPassed;

        stakingToken.transfer(msg.sender, totalUnlocked);
        
        if (userStake.weeksCompleted >= 4) {
            userStake.isUnstaking = false; // Complete the unstaking process
        }

        if (userStake.amount == 0) {
            totalStakers--;
        }
    }

    // Internal function to update energy accrual
    function _updateEnergy(address account) internal {
        StakeInfo storage userStake = stakes[account];
        uint256 timeElapsed = block.timestamp - userStake.lastUpdate;
        userStake.energyAccrued += userStake.amount * timeElapsed * energyRate;
        userStake.lastUpdate = block.timestamp;
    }

    // View function to check how much energy is available for withdrawal
    function availableEnergy(address account) external view returns (uint256) {
        StakeInfo storage userStake = stakes[account];
        uint256 timeElapsed = block.timestamp - userStake.lastUpdate;
        uint256 pendingEnergy = userStake.amount * timeElapsed * energyRate;
        return userStake.energyAccrued + pendingEnergy;
    }

    function setStakingEnabled(bool _enabled) external onlyOwner {
        stakingEnabled = _enabled;
    }

    function setStakingToken(IERC20 _stakingToken) external onlyOwner {
        require(address(_stakingToken) != address(0), "Invalid address");
        require(!stakingEnabled, "Cannot change token when staking is enabled");
        stakingToken = _stakingToken;
    }

    function setEnergyRate(uint256 _energyRate) external onlyOwner {
        energyRate = _energyRate;
    }

    function setEnergyToken(EnergyToken _energyToken) external onlyOwner {
        require(address(_energyToken) != address(0), "Invalid address");
        require(!stakingEnabled, "Cannot change token when staking is enabled");
        energyToken = _energyToken;
    }
}
