// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IEscrow {
    function isDrawdownReady() external view returns (bool);
    function drawdown() external;
}

contract DrawdownManager is ReentrancyGuard {
    address public owner;               // Owner of the contract
    address public ownerNominee;        // Previous owner nominee
    uint256 public nominationDate;      // Date at which ownership transfer was initiated
    address[] public escrowContracts;   // List of escrow contracts

    uint256 public constant NOMINATION_PERIOD = 30 days;

    event OwnerNominated(address indexed newOwner);
    event OwnershipTransferred(address indexed newOwner);
    event NominationCancelled(address indexed cancelledBy);
    event EscrowContractAdded(address indexed escrowContract);
    event EscrowContractRemoved(address indexed escrowContract);
    event DrawdownExecuted(address indexed escrowContract);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // Nominate a new owner, who must accept the nomination
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        ownerNominee = newOwner;
        nominationDate = block.timestamp;
        emit OwnerNominated(newOwner);
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

    // Cancel ownership transfer if it's been over 30 days since the nomination
    function cancelTransfer() external onlyOwner {
        require(block.timestamp >= nominationDate + NOMINATION_PERIOD, "Nomination period not over yet");
        ownerNominee = address(0);
        nominationDate = 0;
        emit NominationCancelled(msg.sender);
    }

    // Add an escrow contract to the list
    function addEscrowContract(address escrowContract) external onlyOwner {
        require(escrowContract != address(0), "Invalid contract address");
        escrowContracts.push(escrowContract);
        emit EscrowContractAdded(escrowContract);
    }

    // Remove an escrow contract from the list
    function removeEscrowContract(address escrowContract) external onlyOwner {
        require(escrowContract != address(0), "Invalid contract address");
        
        for (uint256 i = 0; i < escrowContracts.length; i++) {
            if (escrowContracts[i] == escrowContract) {
                escrowContracts[i] = escrowContracts[escrowContracts.length - 1];
                escrowContracts.pop();
                emit EscrowContractRemoved(escrowContract);
                break;
            }
        }
    }

    // Execute drawdown for all contracts where it's ready
    function executeDrawdowns() external nonReentrant {
        for (uint256 i = 0; i < escrowContracts.length; i++) {
            IEscrow escrow = IEscrow(escrowContracts[i]);

            if (escrow.isDrawdownReady()) {
                try escrow.drawdown() {
                    emit DrawdownExecuted(escrowContracts[i]);
                } catch {
                    // Handle if drawdown fails (optionally, log an error)
                }
            }
        }
    }

    // Get the list of escrow contracts
    function getEscrowContracts() external view returns (address[] memory) {
        return escrowContracts;
    }
}