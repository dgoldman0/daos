// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../utils/ownable.sol";
import "../../iclaimnftmanager.sol";

contract MancalaMatchNFT is ERC721, Ownable {
    uint256 public nextTokenId;
    address public mancalaGame;

    struct MancalaMatch {
        uint256 gameId;
        address playerA;
        address playerB;
        address winner;
        uint256 rounds;
        mapping (uint256 => uint112) boardStates; // Packed board states
    }

    mapping(uint256 => MancalaMatch) public matches; // Mapping of game IDs to match instances
    
    modifier onlyMancalaGame() {
        require(msg.sender == mancalaGame, "Only the MancalaGame contract can call this function");
        _;
    }

    constructor() ERC721("Mancala Match NFT", "MMNFT") {
        nextTokenId = 1;
    }

    function setMancalaGame(address _mancalaGame) public onlyOwner {
        mancalaGame = _mancalaGame;
    }

    function initializeMatch(uint256 gameId, address playerA, address playerB) public onlyMancalaGame {
        require(matches[gameId].gameId == 0, "Match already exists");
        require(nextTokenId == gameId, "Invalid game ID");
        MancalaMatch storage matchdetails = matches[gameId];
        matchdetails.gameId = gameId;
        matchdetails.playerA = playerA;
        matchdetails.playerB = playerB;
        _safeMint(address(this), gameId);
        nextTokenId++;
    }

    // Set winner
    function setWinner(uint256 tokenId, address winner) public onlyMancalaGame {
        require(tokenId < nextTokenId, "Invalid token ID");
        require(winner != address(0), "Invalid winner address");
        require(winner == matches[tokenId].playerA || winner == matches[tokenId].playerB, "Winner must be a player");
        MancalaMatch storage matchdetails = matches[tokenId];
        require(matchdetails.winner == address(0), "Match has already ended");
        matchdetails.winner = winner;
        // Transfer to winner
        _safeTransfer(address(this), winner, tokenId, "");
    }

    // Function that adds a board state to an existing match converting uint8[14] to uint112
    function addBoardState(uint256 tokenId, uint8[14] memory board) public onlyMancalaGame {
        MancalaMatch storage matchdetails = matches[tokenId];
        require(matchdetails.winner == address(0), "Match has already ended");
        matchdetails.boardStates[matchdetails.rounds] = packBoardState(board);
        matchdetails.rounds++;
    }

    // Function to pack a uint8[14] board state into a uint112
    function packBoardState(uint8[14] memory board) public pure returns (uint112) {
        uint112 packedBoard = 0;
        for (uint8 i = 0; i < 14; i++) {
            packedBoard |= uint112(board[i]) << (i * 8);
        }
        return packedBoard;
    }

    // Unpack a uint112 board state into a uint8[14]
    function unpackBoardState(uint112 packedBoard) public pure returns (uint8[14] memory) {
        uint8[14] memory board;
        for (uint8 i = 0; i < 14; i++) {
            board[i] = uint8(packedBoard >> (i * 8));
        }
        return board;
    }
}

// Should have it where the person creating the game can set a prize pool (and even what token it is paid in) where other player would have to match to accept, and the winner gets the pool.
contract MancalaGame is Ownable {
    uint8 constant PLAYER_A_STORE = 6;
    uint8 constant PLAYER_B_STORE = 13;

    enum GameState { Pending, Ongoing, Ended, Cancelled, Rejected }

    address public keyContract; // Contract for NFTs that act as keys to play games
    address public keyDataContract; // Contains the actual data

    address payable public mancalaMatchNFT; // NFT contract for storing match data

    // Minimum health of the key
    uint256 public minKeyHealth;
    // Minimum age of the key
    uint256 public minKeyAge;
    // Minimum number of claims
    uint256 public minKeyClaims;
    // Whether to return keys to the players after the game ends
    bool public returnKeys;

    address public potToken;
    uint256 public potFee;
    bool public returnPotIfRejected;

    uint256 public roundTimeCap = 5 minutes;

    uint256 public requestTimeout = 1 days;

    struct Game {
        uint8[14] board; // 12 pits + 2 stores
        address playerA;
        address playerB;
        address currentPlayer;
        GameState state;
        uint256 requestTime;
        uint256 startTime;
        uint256 keyA;
        uint256 keyB;
        address potToken;
        uint256 potFee;
        uint256 roundStartTime;
    }

    mapping(uint256 => Game) public games; // Mapping of game IDs to game instances

    uint256 public gameIdCounter;
    uint256 public spareGameId;

    event MatchRequested(uint256 gameId, address playerA, address playerB);
    event GameStarted(uint256 gameId, address playerA, address playerB);
    event MoveMade(uint256 gameId, address player, uint8 pitIndex);
    event TurnChanged(uint256 gameId, address currentPlayer);
    event GameEnded(uint256 gameId, address winner, address token, uint256 balance);

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

    constructor(address _keyContract, address _keyDataContract, uint256 _minKeyHealth, uint256 _minKeyAge, uint256 _minKeyClaims, bool _returnKeys, address payable _mancalaMatchNFT, address _potToken, uint256 _potFee, bool _returnPotIfRejected, uint256 _roundTimeCap) Ownable() {
        keyContract = _keyContract;
        keyDataContract = _keyDataContract;
        minKeyHealth = _minKeyHealth;
        minKeyAge = _minKeyAge;
        minKeyClaims = _minKeyClaims;
        returnKeys = _returnKeys;
        mancalaMatchNFT = _mancalaMatchNFT;
        potToken = _potToken;
        potFee = _potFee;
        returnPotIfRejected = _returnPotIfRejected;
        roundTimeCap = _roundTimeCap;
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
    function requestMatch(address opponent, uint256 keyId) public payable returns (uint256) {
        require(opponent != address(0), "Invalid opponent address");
        require(opponent != msg.sender, "Cannot play against yourself");
        // Require that the key is owned by the sender and meets the minimum requirements
        require(IERC721(keyContract).ownerOf(keyId) == msg.sender, "Key is not owned by sender");
        IClaimNFTManager keyManager = IClaimNFTManager(keyDataContract);
        require(keyManager.getHealth(keyId) >= minKeyHealth, "Key health is too low");
        require(keyManager.getMintDate(keyId) <= block.timestamp - minKeyAge, "Key is too young");
        require(keyManager.getTotalClaims(keyId) >= minKeyClaims, "Key has not been claimed enough");

        require(mancalaMatchNFT != address(0), "MancalaMatchNFT contract not set");

        require(potToken == address(0) ? msg.value >= potFee : IERC20(potToken).balanceOf(msg.sender) >= potFee, "Insufficient pot fee");
        // Transfer the key to the contract
        IERC721(keyContract).transferFrom(msg.sender, address(this), keyId);
        uint256 newGameId = gameIdCounter + 1;
        if (spareGameId != 0) {
            newGameId = spareGameId;
            spareGameId = 0;
        } else {
            gameIdCounter += 1;
        }
            
        games[newGameId].requestTime = block.timestamp;
        games[newGameId].playerA = msg.sender;
        games[newGameId].playerB = opponent;
        games[newGameId].keyA = keyId;
        games[newGameId].currentPlayer = msg.sender; // Player A starts

        // Pay the pot
        if (potFee > 0) {
            games[newGameId].potToken = potToken;
            games[newGameId].potFee = potFee;
            if (potToken != address(0)) {
                IERC20(potToken).transferFrom(msg.sender, address(this), potFee);
            } else {
                // Return excess of over
                if (msg.value > potFee) {
                    payable(msg.sender).transfer(msg.value - potFee);
                }
            }
        }
        initializeBoard(games[newGameId].board);
        games[newGameId].state = GameState.Pending;
        emit MatchRequested(newGameId, msg.sender, opponent);
        return newGameId;
    }

    // Accept the game invitation and start the game
    function acceptMatch(uint256 gameId, uint256 keyId) public payable {
        require(games[gameId].playerB == msg.sender, "You are not invited to this game");
        require(games[gameId].state == GameState.Pending, "Game is not pending");
        require(IERC721(keyContract).ownerOf(keyId) == msg.sender, "Key is not owned by sender");
        IClaimNFTManager keyManager = IClaimNFTManager(keyDataContract);
        require(keyManager.getHealth(keyId) >= minKeyHealth, "Key health is too low");
        require(keyManager.getMintDate(keyId) <= block.timestamp - minKeyAge, "Key is too young");
        require(keyManager.getTotalClaims(keyId) >= minKeyClaims, "Key has not been claimed enough");

        require(potToken == address(0) ? msg.value >= potFee : IERC20(potToken).balanceOf(msg.sender) >= potFee, "Insufficient pot fee");

        // Pay the pot (match the address and value of the existing pot for the gameId
        address potToken = games[gameId].potToken;
        uint256 potFee = games[gameId].potFee;
        if (potFee > 0) {
            if (potToken != address(0)) {
                IERC20(potToken).transferFrom(msg.sender, address(this), potFee);
            } else {
                // Return excess of over
                if (msg.value > potFee) {
                    payable(msg.sender).transfer(msg.value - potFee);
                }
            }
        }
        // Transfer the key to the contract
        IERC721(keyContract).transferFrom(msg.sender, address(this), keyId);

        games[gameId].keyB = keyId;
        games[gameId].state = GameState.Ongoing;
        games[gameId].startTime = block.timestamp;
        games[gameId].roundStartTime = block.timestamp;

        MancalaMatchNFT(mancalaMatchNFT).initializeMatch(gameId, games[gameId].playerA, games[gameId].playerB);
        emit GameStarted(gameId, games[gameId].playerA, games[gameId].playerB);
        emit TurnChanged(gameId, games[gameId].currentPlayer);
    }

    // Reject the game invitation
    function rejectMatch(uint256 gameId) public {
        require(games[gameId].playerB == msg.sender, "You are not invited to this game");
        require(games[gameId].state == GameState.Pending, "Game is not pending");
        games[gameId].state = GameState.Rejected;
        spareGameId = gameId;
        IERC721(keyContract).transferFrom(address(this), games[gameId].playerA, games[gameId].keyA);
        if (returnPotIfRejected) {
            address potToken = games[gameId].potToken;
            uint256 potFee = games[gameId].potFee;
            if (potFee > 0) {
                if (potToken != address(0)) {
                    IERC20(potToken).transfer(games[gameId].playerA, potFee);
                } else {
                    payable(games[gameId].playerA).transfer(potFee);
                }
            }
        }
    }

    // Cancel the game if the opponent does not respond within the timeout
    function cancelMatch(uint256 gameId) public {
        require(games[gameId].playerA == msg.sender, "You are not the game creator");
        require(games[gameId].state == GameState.Pending, "Game is not pending");
        require(block.timestamp >= games[gameId].requestTime + requestTimeout, "Timeout has not passed");
        games[gameId].state = GameState.Cancelled;
        spareGameId = gameId;
        IERC721(keyContract).transferFrom(address(this), games[gameId].playerA, games[gameId].keyA);
        if (returnPotIfRejected) {
            address potToken = games[gameId].potToken;
            uint256 potFee = games[gameId].potFee;
            if (potFee > 0) {
                if (potToken != address(0)) {
                    IERC20(potToken).transfer(games[gameId].playerA, potFee);
                } else {
                    payable(games[gameId].playerA).transfer(potFee);
                }
            }
        }
    }

    // Function to move seeds
    function moveSeeds(uint256 gameId, uint8 pitIndex) public onlyPlayer(gameId) isPlayersTurn(gameId) {
        Game storage game = games[gameId];
        require(game.state == GameState.Ongoing, "Game has not started or has already has ended");
        require(pitIndex < 14, "Invalid pit index");
        require(game.board[pitIndex] > 0, "Selected pit is empty");

        // Ensure that there's enough funds for the pot, should the game end
        address potToken = game.potToken;
        uint256 payout = game.potFee  * 2; // Double the pot since it's a 1v1 game
        if (payout > 0) {
            if (potToken != address(0)) {
                require(IERC20(potToken).balanceOf(address(this)) >= payout, "Insufficient pot funds");
            } else {
                require(address(this).balance >= payout, "Insufficient pot funds");
            }
        }
        
        bool extraTurn = false;

        // Ensure the pit belongs to the current player
        if (msg.sender == game.playerA) {
            require(pitIndex >= 0 && pitIndex < 6, "Invalid pit for Player A");
        } else {
            require(pitIndex >= 7 && pitIndex < 13, "Invalid pit for Player B");
        }

        // If the allotted time for the round has passed, end the game w/ the other player as the winner
        if (block.timestamp >= game.roundStartTime + roundTimeCap) {
            game.state = GameState.Ended;
            address winner = (msg.sender == game.playerA) ? game.playerB : game.playerA;
            if (returnKeys) {
                IERC721(keyContract).transferFrom(address(this), game.playerA, game.keyA);
                IERC721(keyContract).transferFrom(address(this), game.playerB, game.keyB);
            }
            // Payout to the winner
            if (payout > 0) {
                if (potToken != address(0)) {
                    IERC20(potToken).transfer(winner, payout);
                } else {
                    payable(winner).transfer(payout);
                }
            }
            emit GameEnded(gameId, winner, potToken, payout);

            return;
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
        extraTurn = ((msg.sender == game.playerA && currentIndex == PLAYER_A_STORE) ||
            (msg.sender == game.playerB && currentIndex == PLAYER_B_STORE));

        // Check if capture is possible: last seed lands in an empty pit on player's own side (except for new stone)
        if ((msg.sender == game.playerA && currentIndex >= 0 && currentIndex < 6 && game.board[currentIndex] == 1) ||
            (msg.sender == game.playerB && currentIndex >= 7 && currentIndex < 13 && game.board[currentIndex] == 1)) {
            captureSeeds(game, currentIndex);
        }

        // Add the board state to the NFT
        MancalaMatchNFT(mancalaMatchNFT).addBoardState(gameId, game.board);

        // Check if the game is over
        if (isGameOver(game)) {
            finalizeGame(gameId);
            return;
        }

        game.roundStartTime = block.timestamp;
        if (!extraTurn) {
            // Switch turns
            game.currentPlayer = (msg.sender == game.playerA) ? game.playerB : game.playerA;
            emit TurnChanged(gameId, game.currentPlayer);
        } else {
            emit TurnChanged(gameId, msg.sender);
        }
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
            // Not sure what to do about draws wrt the NFT
        }

        if (winner != address(0)) {
            MancalaMatchNFT(mancalaMatchNFT).setWinner(gameId, winner);
        }

        // Return keys to the player if enabled
        if (returnKeys) {
            IERC721(keyContract).transferFrom(address(this), game.playerA, game.keyA);
            IERC721(keyContract).transferFrom(address(this), game.playerB, game.keyB);
        }

        // Transfer the pot to the winner
        address potToken = games[gameId].potToken;
        uint256 payout = games[gameId].potFee * 2; // Double the pot since it was paid by both players
        if (payout > 0) {
            if (potToken != address(0)) {
                IERC20(potToken).transfer(winner, payout);
            } else {
                payable(winner).transfer(payout);
            }
        }

        emit GameEnded(gameId, winner, potToken, payout);    
    }

    // Owner only setters for game parameters
    function setKeyContract(address _keyContract) public onlyOwner {
        keyContract = _keyContract;
    }
    function setKeyDataContract(address _keyDataContract) public onlyOwner {
        keyDataContract = _keyDataContract;
    }
    function setMancalaMatchNFT(address payable _mancalaMatchNFT) public onlyOwner {
        mancalaMatchNFT = _mancalaMatchNFT;
    }
    function setMinKeyHealth(uint256 _minKeyHealth) public onlyOwner {
        minKeyHealth = _minKeyHealth;
    }
    function setMinKeyAge(uint256 _minKeyAge) public onlyOwner {
        minKeyAge = _minKeyAge;
    }
    function setMinKeyClaims(uint256 _minKeyClaims) public onlyOwner {
        minKeyClaims = _minKeyClaims;
    }
    function setReturnKeys(bool _returnKeys) public onlyOwner {
        returnKeys = _returnKeys;
    }
    function setPotToken(address _potToken) public onlyOwner {
        potToken = _potToken;
    }
    function setPotFee(uint256 _potFee) public onlyOwner {
        potFee = _potFee;
    }    
    function setReturnPotIfRejected(bool _returnPotIfRejected) public onlyOwner {
        returnPotIfRejected = _returnPotIfRejected;
    }
    function setrequestTimeout(uint256 _requestTimeout) public onlyOwner {
        requestTimeout = _requestTimeout;
    }
    function setRoundTimeCap(uint256 _roundTimeCap) public onlyOwner {
        roundTimeCap = _roundTimeCap;
    }
    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
    function withdrawERC721(address _token, uint256 _tokenId) public onlyOwner {
        IERC721(_token).transferFrom(address(this), owner(), _tokenId);
    }
}
