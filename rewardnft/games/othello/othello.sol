// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Othello game: does not work, may never work.


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

contract OthelloGame is Ownable {
    enum PlayerColor { None, Black, White }

    struct Game {
        uint256 gameId;
        address whitePlayer;
        address blackPlayer;
        uint128 boardState;
        Move[] moves;
        address currentPlayer;
        bool isActive;
    }

    struct Move {
        uint8 position;
        address player;
        uint8[] flippedPositions;
    }

    uint256 private gameCounter;
    mapping(uint256 => Game) public games;

    int8[8] private directions = [-9, -8, -7, -1, 1, 7, 8, 9];

    event GameCreated(uint256 indexed gameId, address indexed blackPlayer, address indexed whitePlayer);
    event MoveMade(uint256 indexed gameId, address indexed player, uint8 position, uint8[] flippedPositions);
    event GameOver(uint256 indexed gameId, address winner);

    function createGame(address opponent) public returns (uint256) {
        // In final version: require(msg.sender != opponent, "Cannot play against yourself");
        uint256 gameId = gameCounter++;
        Game storage game = games[gameId];

        game.gameId = gameId;
        game.blackPlayer = msg.sender;
        game.whitePlayer = opponent;
        game.boardState = initializeBoard();
        game.currentPlayer = game.blackPlayer;
        game.isActive = true;

        emit GameCreated(gameId, msg.sender, opponent);
        return gameId;
    }

    function initializeBoard() internal pure returns (uint128) {
        uint128 board = 0;
        board = setSquare(board, 27, 2);  // White
        board = setSquare(board, 28, 1);  // Black
        board = setSquare(board, 35, 1);  // Black
        board = setSquare(board, 36, 2);  // White
        return board;
    }

    function setSquare(
        uint128 _boardState,
        uint8 _position,
        uint8 _value
    ) internal pure returns (uint128) {
        require(_position < 64, "Position out of bounds");
        require(_value < 3, "Invalid value");

        uint128 mask = uint128(3) << (_position * 2);
        _boardState &= ~mask;
        _boardState |= uint128(_value) << (_position * 2);

        return _boardState;
    }

    function getSquare(uint128 _boardState, uint8 _position) internal pure returns (uint8) {
        require(_position < 64, "Position out of bounds");

        uint128 mask = uint128(3) << (_position * 2);
        uint128 value = (_boardState & mask) >> (_position * 2);

        return uint8(value);
    }

    function makeMove(uint256 gameId, uint8 position) public {
        Game storage game = games[gameId];
        require(game.isActive, "Game is not active");
        require(msg.sender == game.currentPlayer, "Not your turn");

        uint8 squareValue = getSquare(game.boardState, position);
        require(squareValue == 0, "Square is not empty");

        uint8 playerValue = (msg.sender == game.blackPlayer) ? 1 : 2;

        (uint8[] memory piecesToFlip, uint8 flipCount) = validateMove(game.boardState, position, playerValue);
        require(flipCount > 0, "Invalid move");

        game.boardState = setSquare(game.boardState, position, playerValue);

        for (uint8 i = 0; i < flipCount; i++) {
            game.boardState = setSquare(game.boardState, piecesToFlip[i], playerValue);
        }

        game.moves.push(Move({
            position: position,
            player: msg.sender,
            flippedPositions: piecesToFlip
        }));

        emit MoveMade(gameId, msg.sender, position, piecesToFlip);

        // Switch to the next player if they have a valid move
        address nextPlayer = (msg.sender == game.blackPlayer) ? game.whitePlayer : game.blackPlayer;
        if (hasValidMove(game, nextPlayer)) {
            game.currentPlayer = nextPlayer;
        } else if (hasValidMove(game, msg.sender)) {
            // Opponent has no valid moves; current player goes again
            game.currentPlayer = msg.sender;
        } else {
            // No valid moves for both players; game over
            game.isActive = false;
            emit GameOver(gameId, determineWinner(game));
        }
    }

    function validateMove(
        uint128 boardState,
        uint8 position,
        uint8 playerValue
    ) internal view returns (uint8[] memory, uint8) {
        uint8 opponentValue = (playerValue == 1) ? 2 : 1;
        uint8[64] memory piecesToFlip;
        uint8 flipCount = 0;

        for (uint8 dir = 0; dir < 8; dir++) {
            int8 currentPos = int8(position) + directions[dir];
            uint8[7] memory tempFlips;
            uint8 tempCount = 0;
            bool validDirection = false;

            while (isValidPosition(currentPos) && !isEdgeCase(directions[dir], uint8(currentPos), position)) {
                uint8 squareValue = getSquare(boardState, uint8(currentPos));
                if (squareValue == opponentValue) {
                    tempFlips[tempCount++] = uint8(currentPos);
                } else if (squareValue == playerValue) {
                    validDirection = tempCount > 0;
                    break;
                } else {
                    break;
                }
                currentPos += directions[dir];
            }

            if (validDirection) {
                for (uint8 i = 0; i < tempCount; i++) {
                    piecesToFlip[flipCount++] = tempFlips[i];
                }
            }
        }

        uint8[] memory finalFlips = new uint8[](flipCount);
        for (uint8 i = 0; i < flipCount; i++) {
            finalFlips[i] = piecesToFlip[i];
        }

        return (finalFlips, flipCount);
    }

    function isValidPosition(int8 position) internal pure returns (bool) {
        return position >= 0 && position < 64;
    }

    function isEdgeCase(int8 direction, uint8 currentPosition, uint8 originPosition) internal pure returns (bool) {
        uint8 originX = originPosition % 8;
        uint8 originY = originPosition / 8;
        uint8 currentX = currentPosition % 8;
        uint8 currentY = currentPosition / 8;

        // Horizontal moves
        if (direction == 1 || direction == -1) {
            return originY != currentY;
        }

        // Diagonal moves
        if (direction == -9 || direction == -7 || direction == 7 || direction == 9) {
            return (abs(int8(currentX) - int8(originX)) != abs(int8(currentY) - int8(originY)));
        }

        return false;
    }

    function abs(int8 x) internal pure returns (uint8) {
        return uint8(x >= 0 ? x : -x);
    }

    function isGameOver(Game storage game) internal view returns (bool) {
        return !hasValidMove(game, game.blackPlayer) && !hasValidMove(game, game.whitePlayer);
    }

    function hasValidMove(Game storage game, address player) internal view returns (bool) {
        uint8 playerValue = (player == game.blackPlayer) ? 1 : 2;
        for (uint8 i = 0; i < 64; i++) {
            if (getSquare(game.boardState, i) == 0) {
                ( , uint8 flipCount) = validateMove(game.boardState, i, playerValue);
                if (flipCount > 0) {
                    return true;
                }
            }
        }
        return false;
    }

    function determineWinner(Game storage game) internal view returns (address) {
        uint8 blackCount = 0;
        uint8 whiteCount = 0;

        for (uint8 i = 0; i < 64; i++) {
            uint8 squareValue = getSquare(game.boardState, i);
            if (squareValue == 1) {
                blackCount++;
            } else if (squareValue == 2) {
                whiteCount++;
            }
        }

        if (blackCount > whiteCount) {
            return game.blackPlayer;
        } else if (whiteCount > blackCount) {
            return game.whitePlayer;
        } else {
            return address(0);  // Draw
        }
    }
}
