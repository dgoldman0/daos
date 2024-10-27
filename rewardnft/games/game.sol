// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract GameContract is Ownable {
    enum GameState { Pending, Ongoing, Ended, Cancelled, Rejected }

    // Game parameters
    address public keyContract;
    address public keyDataContract;

    uint256 public minKeyHealth;
    uint256 public minKeyAge;
    uint256 public minKeyClaims;
    bool public returnKeys;

    address public potToken; // Address of the token used for pot (or address(0) for ETH)
    uint256 public potFee;

    address public prizeToken; // Address of the token used for prize (or address(0) for ETH)
    uint256 public prizeAmount;
 
    bool public returnPotIfRejected;

    uint256 public roundTimeCap;
    uint256 public requestTimeout;

    // Game structure supporting multiple players
    struct Game {
        address[] players; // Dynamic array for players
        mapping(address => uint256) keys; // Map player addresses to their key IDs
        address currentPlayer; // Tracks the current player
        GameState state;
        uint256 requestTime;
        uint256 startTime;
        address potToken;
        uint256 potFee;
        uint256 roundStartTime;
        // Additional game-specific data can be added in derived contracts
    }

    mapping(uint256 => Game) public games; // Mapping of game IDs to game instances
    uint256 public gameIdCounter;

    // Events
    event MatchRequested(uint256 gameId, address[] players);
    event GameStarted(uint256 gameId, address[] players);
    event GameEnded(uint256 gameId, address winner, address token, uint256 balance);

    // Modifiers
    modifier onlyPlayer(uint256 gameId) {
        require(isPlayer(gameId, msg.sender), "Not a player of this game");
        _;
    }

    modifier isPlayersTurn(uint256 gameId) {
        require(
            msg.sender == games[gameId].currentPlayer,
            "Not your turn"
        );
        _;
    }

    constructor(
        address _keyContract,
        address _keyDataContract,
        uint256 _minKeyHealth,
        uint256 _minKeyAge,
        uint256 _minKeyClaims,
        bool _returnKeys,
        address _potToken,
        uint256 _potFee,
        bool _returnPotIfRejected,
        uint256 _roundTimeCap,
        uint256 _requestTimeout
    ) Ownable() {
        keyContract = _keyContract;
        keyDataContract = _keyDataContract;
        minKeyHealth = _minKeyHealth;
        minKeyAge = _minKeyAge;
        minKeyClaims = _minKeyClaims;
        returnKeys = _returnKeys;
        potToken = _potToken;
        potFee = _potFee;
        returnPotIfRejected = _returnPotIfRejected;
        roundTimeCap = _roundTimeCap;
        requestTimeout = _requestTimeout;
    }

    // Helper function to check if an address is a player in a game
    function isPlayer(uint256 gameId, address player) public view returns (bool) {
        Game storage game = games[gameId];
        for (uint256 i = 0; i < game.players.length; i++) {
            if (game.players[i] == player) {
                return true;
            }
        }
        return false;
    }

    // Request a match with n other players (potentially 0)
    function requestMatch(uint256 keyId) public payable returns (uint256) {
        // Initialize new game ID
        uint256 newGameId = ++gameIdCounter;
        Game storage game = games[newGameId];

        // Set player and validate their key
        game.players.push(msg.sender);
        validateAndTransferKey(newGameId, msg.sender, keyId);

        // Collect pot fee if applicable
        if (potFee > 0) {
            if (potToken != address(0)) {
                require(IERC20(potToken).balanceOf(msg.sender) >= potFee, "Insufficient pot fee");
                IERC20(potToken).transferFrom(msg.sender, address(this), potFee);
            } else {
                require(msg.value >= potFee, "Insufficient pot fee");
                if (msg.value > potFee) {
                    payable(msg.sender).transfer(msg.value - potFee);
                }
            }
        }

        // Initialize game state as Ongoing and set necessary timestamps
        game.state = GameState.Ongoing;
        game.startTime = block.timestamp;
        game.roundStartTime = block.timestamp;
        game.currentPlayer = msg.sender;

        // Call initializeGame to set up any game-specific data
        initializeGame(newGameId);

        // Emit events to signal the game has started
        emit MatchRequested(newGameId, game.players);
        emit GameStarted(newGameId, game.players);

        return newGameId;
    }


    // Accept a match with multiple players
    function acceptMatch(uint256 gameId, uint256 keyId) public payable onlyPlayer(gameId) {
        Game storage game = games[gameId];
        require(game.state == GameState.Pending, "Game is not pending");

        // Validate key for joining player and pay pot fee
        validateAndTransferKey(gameId, msg.sender, keyId);
        collectPotFee(gameId, game.players);

        if (allPlayersReady(gameId)) {
            game.state = GameState.Ongoing;
            game.startTime = block.timestamp;
            game.roundStartTime = block.timestamp;
            game.currentPlayer = game.players[0]; // Start with the first player in the array

            initializeGame(gameId);
            emit GameStarted(gameId, game.players);
        }
    }

    // Helper function to validate keys and transfer them to the contract
    function validateAndTransferKey(uint256 gameId, address player, uint256 keyId) internal {
        require(IERC721(keyContract).ownerOf(keyId) == player, "Key is not owned by sender");
        IClaimNFTManager keyManager = IClaimNFTManager(keyDataContract);
        require(keyManager.getHealth(keyId) >= minKeyHealth, "Key health is too low");
        require(block.timestamp - keyManager.getMintDate(keyId) >= minKeyAge, "Key is too young");
        require(keyManager.getTotalClaims(keyId) >= minKeyClaims, "Key has not been claimed enough");

        IERC721(keyContract).transferFrom(player, address(this), keyId);
        games[gameId].keys[player] = keyId;
    }

    // Function to collect the pot fee for each player
    function collectPotFee(uint256 gameId, address[] memory players) internal {
        Game storage game = games[gameId];
        if (potFee > 0) {
            for (uint256 i = 0; i < players.length; i++) {
                address player = players[i];
                if (potToken != address(0)) {
                    require(IERC20(potToken).balanceOf(player) >= potFee, "Insufficient pot fee");
                    IERC20(potToken).transferFrom(player, address(this), potFee);
                } else {
                    require(msg.value >= potFee, "Insufficient pot fee");
                    if (msg.value > potFee) {
                        payable(player).transfer(msg.value - potFee);
                    }
                }
            }
            game.potFee = potFee;
            game.potToken = potToken;
        }
    }

    // Check if all players are ready to start the game
    function allPlayersReady(uint256 gameId) internal view returns (bool) {
        Game storage game = games[gameId];
        for (uint256 i = 0; i < game.players.length; i++) {
            if (game.keys[game.players[i]] == 0) {
                return false;
            }
        }
        return true;
    }

    /* Abstract functions to get various game info, such as how many players are allowed, etc. */
    // Returns the minimum number of players required to start the game
    function getMinPlayers() public view virtual returns (uint256);

    // Returns the maximum number of players allowed in the game
    function getMaxPlayers() public view virtual returns (uint256);

    // Checks if the game is ready to start based on game-specific conditions
    function isGameReady(uint256 gameId) internal view virtual returns (bool);

    // Abstract function to initialize game-specific data
    function initializeGame(uint256 gameId) internal virtual;
        
    // Owner-only setter functions
    function setKeyContract(address _keyContract) public onlyOwner {
        keyContract = _keyContract;
    }

    function setKeyDataContract(address _keyDataContract) public onlyOwner {
        keyDataContract = _keyDataContract;
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

    function setPrizeToken(address _prizeToken) public onlyOwner {
        prizeToken = _prizeToken;
    }

    function setPrizeAmount(uint256 _prizeAmount) public onlyOwner {
        prizeAmount = _prizeAmount;
    }

    function setReturnPotIfRejected(bool _returnPotIfRejected) public onlyOwner {
        returnPotIfRejected = _returnPotIfRejected;
    }

    function setRoundTimeCap(uint256 _roundTimeCap) public onlyOwner {
        roundTimeCap = _roundTimeCap;
    }

    function setRequestTimeout(uint256 _requestTimeout) public onlyOwner {
        requestTimeout = _requestTimeout;
    }

    // ERC721 Receiver function
    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // Function to withdraw ERC721 tokens (admin only)
    function withdrawERC721(address _token, uint256 _tokenId) public onlyOwner {
        IERC721(_token).transferFrom(address(this), owner(), _tokenId);
    }
}
