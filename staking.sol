// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";  // Import ReentrancyGuard

contract StakingContract is Ownable, ReentrancyGuard {  // Inherit ReentrancyGuard
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public totalStaked;
    uint256 public constant weekDuration = 7 days;

    struct StakeInfo {
        uint256 stakedAmount;
        uint256 rewardPerTokenPaid;
        uint256 rewards;

        uint256 unstakeRequestTime;
        uint256 unstakeAmount;
        uint256 weeksClaimed;
        bool isUnstaking;
    }

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount);
    event UnstakeRequested(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event UnstakeCancelled(address indexed user);
    event RewardsClaimed(address indexed user, uint256 reward);

    constructor(IERC20 _stakingToken, IERC20 _rewardToken, uint256 _rewardRate) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    // Allow owner to change owner
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        ownerNominee = newOwner;
        emit OwnerNominated(newOwner);
    }

    // Revert ownership if it's been over 30 days since the transfer.
    function cancelTransfer() external onlyOwner{
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
        emit OwnershipTransferred(owner);
    }

    // Reject the ownership transfer
    function rejectOwnership() external {
        require(msg.sender == ownerNominee, "Only the nominee can reject ownership");
        ownerNominee = address(0);
        nominationDate = 0;
        emit NominationCancelled(msg.sender);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            stakes[account].rewards = earned(account);
            stakes[account].rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((block.timestamp - lastUpdateTime) * rewardRate * 1e18) /
            totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        return
            (stakes[account].stakedAmount *
                (rewardPerToken() - stakes[account].rewardPerTokenPaid)) /
            1e18 + stakes[account].rewards;
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {  // Apply nonReentrant
        require(amount > 0, "Cannot stake 0");

        stakingToken.transferFrom(msg.sender, address(this), amount);

        totalStaked += amount;
        stakes[msg.sender].stakedAmount += amount;

        emit Staked(msg.sender, amount);
    }

    function requestUnstake(uint256 amount) external nonReentrant updateReward(msg.sender) {  // Apply nonReentrant
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.stakedAmount >= amount, "Insufficient stake");
        require(!stakeInfo.isUnstaking, "Unstaking process already active");

        stakeInfo.unstakeRequestTime = block.timestamp;
        stakeInfo.unstakeAmount = amount;
        stakeInfo.isUnstaking = true;
        stakeInfo.weeksClaimed = 0;

        emit UnstakeRequested(msg.sender, amount);
    }

    function unstake() external nonReentrant updateReward(msg.sender) {  // Apply nonReentrant
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.isUnstaking, "No active unstake request");

        uint256 weeksPassed = (block.timestamp - stakeInfo.unstakeRequestTime) / weekDuration;
        require(weeksPassed > stakeInfo.weeksClaimed, "No additional weeks unlocked yet");

        uint256 weeksToClaim = weeksPassed - stakeInfo.weeksClaimed;
        uint256 maxWeeks = 4 - stakeInfo.weeksClaimed;
        uint256 weeksToUnstake = weeksToClaim > maxWeeks ? maxWeeks : weeksToClaim;

        uint256 amountToUnstake = (stakeInfo.unstakeAmount * weeksToUnstake) / 4;

        require(amountToUnstake > 0, "Nothing to unstake yet");

        stakeInfo.stakedAmount -= amountToUnstake;
        totalStaked -= amountToUnstake;

        stakeInfo.weeksClaimed += weeksToUnstake;

        if (stakeInfo.weeksClaimed >= 4) {
            stakeInfo.isUnstaking = false;
            stakeInfo.unstakeAmount = 0;
            stakeInfo.weeksClaimed = 0;
            stakeInfo.unstakeRequestTime = 0;
        }

        stakingToken.transfer(msg.sender, amountToUnstake);

        emit Unstaked(msg.sender, amountToUnstake);
    }

    function cancelUnstake() external nonReentrant {  // Apply nonReentrant
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.isUnstaking, "No active unstake request to cancel");

        stakeInfo.isUnstaking = false;
        stakeInfo.unstakeAmount = 0;
        stakeInfo.unstakeRequestTime = 0;
        stakeInfo.weeksClaimed = 0;

        emit UnstakeCancelled(msg.sender);
    }

    function claimReward() external nonReentrant updateReward(msg.sender) {  // Apply nonReentrant
        uint256 reward = stakes[msg.sender].rewards;
        require(reward > 0, "No rewards to claim");

        stakes[msg.sender].rewards = 0;
        rewardToken.transfer(msg.sender, reward);

        emit RewardsClaimed(msg.sender, reward);
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) {
        rewardRate = _rewardRate;
    }

    // Allow the owner to withdraw any mistakenly deposited ETH or other ERC-20 tokens
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH balance to withdraw");
        payable(owner).transfer(balance);
    }

    function withdrawOtherTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        uint256 withdrawAmount = balance;
        require(balance > 0, "No token balance to withdraw");
        // Only allow drawing OVER the staked amount
        if (tokenAddress == address(stakingToken)) {
            require(balance > totalStaked, "Cannot withdraw staked tokens");
            withdrawAmount = balance - totalStaked;
        }
        require(token.transfer(owner, balance), "Token transfer failed");
    }

    // Fallback function to receive ETH
    receive() external payable {}

}
