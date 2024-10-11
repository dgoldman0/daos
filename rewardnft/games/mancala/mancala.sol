// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../utils/ownable.sol";

// Will create a game NFT as well and a token representing ownership of that game. It'll include a copy of the final game state, the players, as well as each turn.abi
// Scrap so far
/*
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MancalaMatchNFT is ERC1155 {
    uint256 public gameIdCounter;

    struct Match {
        address playerA;
        address playerB;
        uint256 gameId;
        // List of boards for each turn
        uint8[14] finalBoard;
    }

    constructor() ERC1155("https://arcadium.games/api/mancala/{id}.json") {}

    function mintMatchNFT(address owner, uint256 gameId) public {
        gameIdCounter += 1;
        _mint(owner, gameIdCounter, 1, "");
    }

    // Mint ERC-20 token representing ownership of the game
    function mintMatchCoinage(address owner, uint256 gameId) public {
        gameIdCounter += 1;
        _mint(owner, gameIdCounter, 1, "");
    }
}
*/

// Needed so the game can interact with the NFT's internal data
interface IClaimNFTManager {
    function getHealth(uint256 tokenId) external view returns (uint256);
    function getMintDate(uint256 tokenId) external view returns (uint256);
    function getTotalClaims(uint256 tokenId) external view returns (uint256);
}

contract MancalaGame is Ownable {
    uint8 constant PLAYER_A_STORE = 6;
    uint8 constant PLAYER_B_STORE = 13;

    enum GameState { Pending, Ongoing, Ended, Cancelled }

    address public keyContract; // Contract for NFTs that act as keys to play games
    address public keyDataContract; // Contains the actual data
    // Minimum health of the key
    uint256 public minKeyHealth;
    // Minimum age of the key
    uint256 public minKeyAge;
    // Minimum number of claims
    uint256 public minKeyClaims;

    uint256 public requestTimeout = 1 days;

    struct Game {
        uint8[14] board; // 12 pits + 2 stores
        address playerA;
        address playerB;
        address currentPlayer;
        GameState state;
        uint256 requestTime;
        uint256 keyA;
        uint256 keyB;
    }

    mapping(uint256 => Game) public games; // Mapping of game IDs to game instances
    uint256 public gameIdCounter;

    event MatchRequested(uint256 gameId, address playerA, address playerB);
    event GameStarted(uint256 gameId, address playerA, address playerB);
    event MoveMade(uint256 gameId, address player, uint8 pitIndex);
    event TurnChanged(uint256 gameId, address currentPlayer);
    event GameEnded(uint256 gameId, address winner);

    modifier onlyPlayer(uint256 gameId) {
        require(
            msg.sender == games[gameId].playerA || msg.sender == games[gameId].playerB,
            "Not a player of this game"
        );
        _;
    }

    modifier isPlayersTurn(uint256 gameId) {
        require(
            msg.sender == games[gameId].currentPlayer,
            "Not your turn"
        );
        _;
    }

    constructor(address _keyContract, address _keyDataContract, uint256 _minKeyHealth, uint256 _minKeyAge, uint256 _minKeyClaims) Ownable() {
        keyContract = _keyContract;
        keyDataContract = _keyDataContract;
        minKeyHealth = _minKeyHealth;
        minKeyAge = _minKeyAge;
        minKeyClaims = _minKeyClaims;
    }

    // Get the players of a given game
    function getPlayers(uint256 gameId) public view returns (address, address) {
        return (games[gameId].playerA, games[gameId].playerB);
    }

    // Return the board of a given game
    function getBoard(uint256 gameId) public view returns (uint8[14] memory) {
        return games[gameId].board;
    }

    // Return the current player of a given game
    function getCurrentPlayer(uint256 gameId) public view returns (address) {
        return games[gameId].currentPlayer;
    }

    // Return the state of a given game
    function getGameState(uint256 gameId) public view returns (GameState) {
        return games[gameId].state;
    }

    // Initialize the board with 4 seeds in each pit and 0 in stores
    function initializeBoard(uint8[14] storage board) internal {
        for (uint8 i = 0; i < 6; i++) {
            board[i] = 4; // Player A's side
            board[i + 7] = 4; // Player B's side
        }
        board[PLAYER_A_STORE] = 0; // Player A's store
        board[PLAYER_B_STORE] = 0; // Player B's store
    }

    // Function to start a new game
    function requestMatch(address opponent, uint256 keyId) public returns (uint256) {
        require(opponent != address(0), "Invalid opponent address");
        require(opponent != msg.sender, "Cannot play against yourself");
        // Require that the key is owned by the sender and meets the minimum requirements
        require(IERC721(keyContract).ownerOf(keyId) == msg.sender, "Key is not owned by sender");
        IClaimNFTManager keyManager = IClaimNFTManager(keyDataContract);
        require(keyManager.getHealth(keyId) >= minKeyHealth, "Key health is too low");
        require(keyManager.getMintDate(keyId) <= block.timestamp - minKeyAge, "Key is too young");
        require(keyManager.getTotalClaims(keyId) >= minKeyClaims, "Key has not been claimed enough");
        // Transfer the key to the contract
        IERC721(keyContract).transferFrom(msg.sender, address(this), keyId);
        gameIdCounter += 1;
        uint256 newGameId = gameIdCounter;
        games[newGameId].requestTime = block.timestamp;
        games[newGameId].playerA = msg.sender;
        games[newGameId].playerB = opponent;
        games[newGameId].keyA = keyId;
        games[newGameId].currentPlayer = msg.sender; // Player A starts
        initializeBoard(games[newGameId].board);
        games[newGameId].state = GameState.Pending;
        emit MatchRequested(newGameId, msg.sender, opponent);
        return newGameId;
    }

    // Accept the game invitation and start the game
    function acceptMatch(uint256 gameId, uint256 keyId) public {
        require(games[gameId].playerB == msg.sender, "You are not invited to this game");
        require(games[gameId].state == GameState.Pending, "Game is not pending");
        require(IERC721(keyContract).ownerOf(keyId) == msg.sender, "Key is not owned by sender");
        IClaimNFTManager keyManager = IClaimNFTManager(keyDataContract);
        require(keyManager.getHealth(keyId) >= minKeyHealth, "Key health is too low");
        require(keyManager.getMintDate(keyId) <= block.timestamp - minKeyAge, "Key is too young");
        require(keyManager.getTotalClaims(keyId) >= minKeyClaims, "Key has not been claimed enough");

        // Transfer the key to the contract
        IERC721(keyContract).transferFrom(msg.sender, address(this), keyId);
        games[gameId].keyB = keyId;
        games[gameId].state = GameState.Ongoing;
        emit GameStarted(gameId, games[gameId].playerA, games[gameId].playerB);
        emit TurnChanged(gameId, games[gameId].currentPlayer);
    }

    // Reject the game invitation
    function rejectMatch(uint256 gameId) public {
        require(games[gameId].playerB == msg.sender, "You are not invited to this game");
        require(games[gameId].state == GameState.Pending, "Game is not pending");
        games[gameId].state = GameState.Ended;
        // Transfer the key back to the player
        IERC721(keyContract).transferFrom(address(this), games[gameId].playerA, games[gameId].keyA);
    }

    // Cancel the game if the opponent does not respond within the timeout
    function cancelMatch(uint256 gameId) public {
        require(games[gameId].playerA == msg.sender, "You are not the game creator");
        require(games[gameId].state == GameState.Pending, "Game is not pending");
        require(block.timestamp >= games[gameId].requestTime + requestTimeout, "Timeout has not passed");
        games[gameId].state = GameState.Cancelled;
        // Transfer the key back to the player
        IERC721(keyContract).transferFrom(address(this), games[gameId].playerA, games[gameId].keyA);
    }

    // Function to move seeds
    function moveSeeds(uint256 gameId, uint8 pitIndex) public onlyPlayer(gameId) isPlayersTurn(gameId) {
        Game storage game = games[gameId];
        require(game.state == GameState.Ongoing, "Game has not started or has already has ended");
        require(pitIndex < 14, "Invalid pit index");
        require(game.board[pitIndex] > 0, "Selected pit is empty");

        // Ensure the pit belongs to the current player
        if (msg.sender == game.playerA) {
            require(pitIndex >= 0 && pitIndex < 6, "Invalid pit for Player A");
        } else {
            require(pitIndex >= 7 && pitIndex < 13, "Invalid pit for Player B");
        }

        uint8 seeds = game.board[pitIndex];
        game.board[pitIndex] = 0;
        uint8 currentIndex = pitIndex;

        while (seeds > 0) {
            currentIndex = (currentIndex + 1) % 14;
            
            // Skip opponent's store
            if (msg.sender == game.playerA && currentIndex == PLAYER_B_STORE) continue;
            if (msg.sender == game.playerB && currentIndex == PLAYER_A_STORE) continue;

            game.board[currentIndex]++;
            seeds--;
        }

        emit MoveMade(gameId, msg.sender, pitIndex);

        // Check if last seed landed in player's store for extra turn
        if ((msg.sender == game.playerA && currentIndex == PLAYER_A_STORE) ||
            (msg.sender == game.playerB && currentIndex == PLAYER_B_STORE)) {
            emit TurnChanged(gameId, msg.sender); // Player gets an extra turn
            return;
        }

        // Check if capture is possible
        if ((msg.sender == game.playerA && currentIndex >= 0 && currentIndex < 6 && game.board[currentIndex] == 1) ||
            (msg.sender == game.playerB && currentIndex >= 7 && currentIndex < 13 && game.board[currentIndex] == 1)) {
            captureSeeds(game, currentIndex);
        }

        // Check if the game is over
        if (isGameOver(game)) {
            finalizeGame(gameId);
            return;
        }

        // Switch turns
        game.currentPlayer = (msg.sender == game.playerA) ? game.playerB : game.playerA;
        emit TurnChanged(gameId, game.currentPlayer);
    }

    // Capture seeds from the opposite pit
    function captureSeeds(Game storage game, uint8 pitIndex) internal {
        uint8 oppositeIndex = 12 - pitIndex;
        if (game.board[oppositeIndex] > 0) {
            if (pitIndex < 6) {
                // Player A captures
                game.board[PLAYER_A_STORE] += game.board[oppositeIndex] + game.board[pitIndex];
            } else {
                // Player B captures
                game.board[PLAYER_B_STORE] += game.board[oppositeIndex] + game.board[pitIndex];
            }
            game.board[oppositeIndex] = 0;
            game.board[pitIndex] = 0;
        }
    }

    // Function to check for game end
    function isGameOver(Game storage game) internal view returns (bool) {
        uint8 playerASum = 0;
        uint8 playerBSum = 0;

        for (uint8 i = 0; i < 6; i++) {
            playerASum += game.board[i];
            playerBSum += game.board[i + 7];
        }

        return (playerASum == 0 || playerBSum == 0);
    }

    // Function to collect remaining seeds after the game ends
    function collectRemainingSeeds(Game storage game) internal {
        for (uint8 i = 0; i < 6; i++) {
            game.board[PLAYER_A_STORE] += game.board[i];
            game.board[PLAYER_B_STORE] += game.board[i + 7];
            game.board[i] = 0;
            game.board[i + 7] = 0;
        }
    }

    // Finalize the game and declare the winner
    function finalizeGame(uint256 gameId) internal {
        Game storage game = games[gameId];
        collectRemainingSeeds(game);
        game.state = GameState.Ended;

        address winner;
        if (game.board[PLAYER_A_STORE] > game.board[PLAYER_B_STORE]) {
            winner = game.playerA;
        } else if (game.board[PLAYER_A_STORE] < game.board[PLAYER_B_STORE]) {
            winner = game.playerB;
        } else {
            winner = address(0); // Draw
        }

        emit GameEnded(gameId, winner);
    }
}
