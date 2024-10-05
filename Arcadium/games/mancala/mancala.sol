// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MancalaGame {
    uint8 constant PLAYER_A_STORE = 6;
    uint8 constant PLAYER_B_STORE = 13;

    enum GameState { Ongoing, Ended }

    struct Game {
        uint8[14] board; // 12 pits + 2 stores
        address playerA;
        address playerB;
        address currentPlayer;
        GameState state;
    }

    mapping(uint256 => Game) public games; // Mapping of game IDs to game instances
    uint256 public gameIdCounter;

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
    function startGame(address opponent) public {
        uint256 newGameId = gameIdCounter++;
        games[newGameId].playerA = msg.sender;
        games[newGameId].playerB = opponent;
        games[newGameId].currentPlayer = msg.sender; // Player A starts
        initializeBoard(games[newGameId].board);
        games[newGameId].state = GameState.Ongoing;

        emit GameStarted(newGameId, msg.sender, opponent);
    }

    // Function to move seeds
    function moveSeeds(uint256 gameId, uint8 pitIndex) public onlyPlayer(gameId) isPlayersTurn(gameId) {
        Game storage game = games[gameId];
        require(game.state == GameState.Ongoing, "Game has ended");
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
