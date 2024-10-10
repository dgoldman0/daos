// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts@4.9.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.0/security/ReentrancyGuard.sol";

// Ownable contract: Custom
contract Ownable is ReentrancyGuard {
    address private _owner;
    address public ownerNominee;
    uint256 public nominationDate;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnerNominated(address indexed newOwner);
    event NominationCancelled(address indexed cancelledBy);

    constructor() {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not the owner");
        _;
    }

    // Allow owner to change owner
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        ownerNominee = newOwner;
        nominationDate = block.timestamp;   
        emit OwnerNominated(newOwner);
    }

    // Revert ownership
    function cancelTransfer() external onlyOwner {
        ownerNominee = address(0);
        nominationDate = 0;
        emit NominationCancelled(msg.sender);
    }

    function acceptOwnership() external {
        require(msg.sender == ownerNominee, "Only the nominee can accept ownership");
        address previousOwner = _owner;
        _owner = ownerNominee;
        ownerNominee = address(0);
        nominationDate = 0;
        emit OwnershipTransferred(previousOwner, _owner);
    }
    // Reject the ownership transfer
    function rejectOwnership() external {
        require(msg.sender == ownerNominee, "Only the nominee can reject ownership");
        ownerNominee = address(0);
        nominationDate = 0;
        emit NominationCancelled(msg.sender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    // Withdraw function for the owner to withdraw tokens held by the contract.
    function withdraw(address _token) public onlyOwner nonReentrant {
        if (_token == address(0)) {
            payable(owner()).transfer(address(this).balance);
        } else {
            IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
        }
    }

    // Since owner can withdraw ether the contract can receive ether
    receive() external payable {}
}