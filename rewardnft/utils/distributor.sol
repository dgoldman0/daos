// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ownable.sol";

contract TimeBasedEscrow is Ownable {
    address public beneficiary;  // The beneficiary of the funds
    uint256 public drawdownAmountPerDay;   // Fixed amount of tokens released per day
    uint256 public lastDrawdownTime;       // Timestamp of the last withdrawal
    IERC20 public escrowToken;             // Token used for the escrow

    uint256 public totalDrawn;    // Tracks total amount of tokens drawn so far
    uint256 public constant MINIMUM_DRAWDOWN_INTERVAL = 1 hours; // Minimum time between drawdowns (1 hour)

    event Drawdown(address indexed trigger, uint256 amount);

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
}