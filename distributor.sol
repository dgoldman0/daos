// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TimeBasedEscrow {
    address public beneficiary;  // The beneficiary of the funds
    address public ownerNominee;     // Previous owner of the contract, if any.
    uint256 public nominationDate; // Date at which ownership transfer occurred.
    address public owner;        // Owner of the contract
    uint256 public drawdownAmountPerDay;   // Fixed amount of tokens released per day
    uint256 public lastDrawdownTime;       // Timestamp of the last withdrawal
    IERC20 public escrowToken;             // Token used for the escrow

    uint256 public totalDrawn;    // Tracks total amount of tokens drawn so far
    uint256 public constant MINIMUM_DRAWDOWN_INTERVAL = 1 hours; // Minimum time between drawdowns (1 hour)

    event Drawdown(address indexed trigger, uint256 amount);
    event OwnershipTransferred(address indexed newOwner);
    event OwnerNominated(address indexed newOwner);
    event NominationCancelled(address indexed cancelledBy);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor(
        address _beneficiary,
        address _escrowToken,
        uint256 _drawdownAmountPerDay
    ) {
        beneficiary = _beneficiary;
        escrowToken = IERC20(_escrowToken);
        drawdownAmountPerDay = _drawdownAmountPerDay;
        owner = msg.sender;
        lastDrawdownTime = block.timestamp;  // Set the start of the drawdown period
    }

    // Allow owner to change owner
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        ownerNominee = newOwner;
        emit OwnerNominated(newOwner);
    }

    // Revert ownership if it's been over 30 days since the transfer.
    function cancelTransfer() external {
        require(owner == msg.sender, "Not owner");
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

    // Function to calculate the amount available for withdrawal based on the number of days since the last drawdown
    function availableForWithdrawal() public view returns (uint256) {
        uint256 timeSinceLastDrawdown = block.timestamp - lastDrawdownTime;
        uint256 daysSinceLastDrawdown = timeSinceLastDrawdown / 1 days;
        uint256 fractionalDay = (timeSinceLastDrawdown % 1 days) * drawdownAmountPerDay / 1 days;
        uint256 availableAmount = (daysSinceLastDrawdown * drawdownAmountPerDay) + fractionalDay;
        if (availableAmount > escrowToken.balanceOf(address(this))) {
            availableAmount = escrowToken.balanceOf(address(this));
        }
        return availableAmount;
    }

    // Function to check if a drawdown is possible (1-hour minimum interval)
    function isDrawdownReady() public view returns (bool) {
        return (block.timestamp >= lastDrawdownTime + MINIMUM_DRAWDOWN_INTERVAL);
    }

    // Function to withdraw the available amount (can be called by anyone)
    function drawdown() external {
        require(isDrawdownReady(), "Drawdown not ready yet. Wait for the minimum interval to pass.");

        uint256 amountToWithdraw = availableForWithdrawal();
        require(amountToWithdraw > 0, "Nothing to withdraw yet");

        // Update state
        lastDrawdownTime = block.timestamp;
        totalDrawn += amountToWithdraw;

        // Transfer the available amount to the beneficiary
        require(escrowToken.transfer(beneficiary, amountToWithdraw), "Transfer failed");

        emit Drawdown(msg.sender, amountToWithdraw);
    }

    // Allow the owner to withdraw any mistakenly deposited ETH or other ERC-20 tokens
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH balance to withdraw");
        payable(owner).transfer(balance);
    }

    function withdrawOtherTokens(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(escrowToken), "Cannot withdraw escrow tokens");
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No token balance to withdraw");
        require(token.transfer(owner, balance), "Token transfer failed");
    }

    // Fallback function to receive ETH
    receive() external payable {}
}