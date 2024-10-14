// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../utils/ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Needed so the game can interact with the key's data
interface IClaimNFTManager {
    function getHealth(uint256 tokenId) external view returns (uint256);
    function getMintDate(uint256 tokenId) external view returns (uint256);
    function getTotalClaims(uint256 tokenId) external view returns (uint256);
}

contract ChessGame is Ownable {
    // Key system variables
    address public keyContract; // Contract for NFTs that act as keys to play games
    address public keyDataContract; // Contains the actual data
    uint256 public minKeyHealth;
    uint256 public minKeyAge;
    uint256 public minKeyClaims;

    // Game management variables
    enum GameState { Pending, Ongoing, Ended, Cancelled, Draw, WhiteWon, BlackWon }

    struct Game {
        uint256 gameId;
        int8[64] board;
        bool whiteTurn;
        // Castling rights
        bool whiteKingMoved;
        bool whiteRookKingSideMoved;
        bool whiteRookQueenSideMoved;
        bool blackKingMoved;
        bool blackRookKingSideMoved;
        bool blackRookQueenSideMoved;
        int8 enPassantTarget;
        uint256 halfmoveClock;
        GameState gameState;
        uint256 moveNumber;
        address playerWhite;
        address playerBlack;
        uint256 keyWhite;
        uint256 keyBlack;
        uint256 requestTime;
        mapping(bytes32 => uint8) positionOccurrences;
    }

    struct MoveData {
        int8 piece;
        int8 targetPiece;
        bool resetHalfmoveClock;
        bool isEnPassantMove;
        uint8 capturedPawnIndex;
        bool isCastlingMove;
        uint8 rookFrom;
        uint8 rookTo;
        int8 previousEnPassantTarget;
        bytes32 positionHash;
    }

    mapping(uint256 => Game) public games;
    uint256 public gameIdCounter;
    uint256 public spareGameId;
    uint256 public requestTimeout = 1 days;

    // Events
    event MatchRequested(uint256 gameId, address playerWhite, address playerBlack);
    event GameStarted(uint256 gameId, address playerWhite, address playerBlack);
    event MoveMade(uint256 gameId, address player, uint8 fromIndex, uint8 toIndex);
    event GameEnded(uint256 gameId, GameState result);

    // Modifiers
    modifier onlyPlayer(uint256 gameId) {
        require(
            msg.sender == games[gameId].playerWhite || msg.sender == games[gameId].playerBlack,
            "Not a player of this game"
        );
        _;
    }

    modifier isPlayersTurn(uint256 gameId) {
        require(
            (msg.sender == games[gameId].playerWhite && games[gameId].whiteTurn) ||
            (msg.sender == games[gameId].playerBlack && !games[gameId].whiteTurn),
            "Not your turn"
        );
        _;
    }

    // Constructor
    constructor(address _keyContract, address _keyDataContract, uint256 _minKeyHealth, uint256 _minKeyAge, uint256 _minKeyClaims) Ownable() {
        keyContract = _keyContract;
        keyDataContract = _keyDataContract;
        minKeyHealth = _minKeyHealth;
        minKeyAge = _minKeyAge;
        minKeyClaims = _minKeyClaims;
    }

    // Function to request a match
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

        uint256 newGameId = gameIdCounter + 1;
        if (spareGameId != 0) {
            newGameId = spareGameId;
            spareGameId = 0;
        } else {
            gameIdCounter += 1;
        }

        Game storage game = games[newGameId];
        game.gameId = newGameId;
        game.playerWhite = msg.sender;
        game.playerBlack = opponent;
        game.keyWhite = keyId;
        game.requestTime = block.timestamp;
        game.gameState = GameState.Pending;

        emit MatchRequested(newGameId, msg.sender, opponent);

        return newGameId;
    }

    // Accept the game invitation and start the game
    function acceptMatch(uint256 gameId, uint256 keyId) public {
        Game storage game = games[gameId];
        require(game.playerBlack == msg.sender, "You are not invited to this game");
        require(game.gameState == GameState.Pending, "Game is not pending");

        // Require that the key is owned by the sender and meets the minimum requirements
        require(IERC721(keyContract).ownerOf(keyId) == msg.sender, "Key is not owned by sender");
        IClaimNFTManager keyManager = IClaimNFTManager(keyDataContract);
        require(keyManager.getHealth(keyId) >= minKeyHealth, "Key health is too low");
        require(keyManager.getMintDate(keyId) <= block.timestamp - minKeyAge, "Key is too young");
        require(keyManager.getTotalClaims(keyId) >= minKeyClaims, "Key has not been claimed enough");

        // Transfer the key to the contract
        IERC721(keyContract).transferFrom(msg.sender, address(this), keyId);

        game.keyBlack = keyId;
        game.gameState = GameState.Ongoing;

        initializeGame(gameId);

        emit GameStarted(gameId, game.playerWhite, game.playerBlack);
    }

    // Initialize the game
    function initializeGame(uint256 gameId) internal {
        Game storage game = games[gameId];
        // Initialize board
        initializeBoard(game.board);
        game.whiteTurn = true;
        game.enPassantTarget = -1;
        game.halfmoveClock = 0;
        game.moveNumber = 1;
        // Initialize castling rights
        game.whiteKingMoved = false;
        game.whiteRookKingSideMoved = false;
        game.whiteRookQueenSideMoved = false;
        game.blackKingMoved = false;
        game.blackRookKingSideMoved = false;
        game.blackRookQueenSideMoved = false;
    }

    // Initialize the board
    function initializeBoard(int8[64] storage board) internal {
        // White pieces
        board[0] = 4;   // Rook
        board[1] = 2;   // Knight
        board[2] = 3;   // Bishop
        board[3] = 5;   // Queen
        board[4] = 6;   // King
        board[5] = 3;   // Bishop
        board[6] = 2;   // Knight
        board[7] = 4;   // Rook
        for (uint8 i = 8; i < 16; i++) {
            board[i] = 1; // Pawns
        }
        // Black pieces
        board[56] = -4;  // Rook
        board[57] = -2;  // Knight
        board[58] = -3;  // Bishop
        board[59] = -5;  // Queen
        board[60] = -6;  // King
        board[61] = -3;  // Bishop
        board[62] = -2;  // Knight
        board[63] = -4;  // Rook
        for (uint8 i = 48; i < 56; i++) {
            board[i] = -1; // Pawns
        }
        // Empty squares
        for (uint8 i = 16; i < 48; i++) {
            board[i] = 0;
        }
    }

    // Reject the game invitation
    function rejectMatch(uint256 gameId) public {
        Game storage game = games[gameId];
        require(game.playerBlack == msg.sender, "You are not invited to this game");
        require(game.gameState == GameState.Pending, "Game is not pending");
        game.gameState = GameState.Ended;
        spareGameId = gameId;
        // Return key to playerWhite
        IERC721(keyContract).transferFrom(address(this), game.playerWhite, game.keyWhite);
    }

    // Cancel the game if the opponent does not respond within the timeout
    function cancelMatch(uint256 gameId) public {
        Game storage game = games[gameId];
        require(game.playerWhite == msg.sender, "You are not the game creator");
        require(game.gameState == GameState.Pending, "Game is not pending");
        require(block.timestamp >= game.requestTime + requestTimeout, "Timeout has not passed");
        game.gameState = GameState.Cancelled;
        spareGameId = gameId;
        // Return key to playerWhite
        IERC721(keyContract).transferFrom(address(this), game.playerWhite, game.keyWhite);
    }

    // Modified move function
    function move(uint256 gameId, uint8 fromIndex, uint8 toIndex, uint8 promotionChoice)
        public
        onlyPlayer(gameId)
        isPlayersTurn(gameId)
        returns (bool)
    {
        Game storage game = games[gameId];
        require(game.gameState == GameState.Ongoing, "Game is not ongoing");
        require(fromIndex < 64 && toIndex < 64, "Invalid index.");

        // Phase 1: Validation and preparation
        MoveData memory moveData = validateAndPrepareMove(game, fromIndex, toIndex, promotionChoice);

        // Phase 2: Execution of the move
        executeMove(game, fromIndex, toIndex, promotionChoice, moveData);

        // Phase 3: Post-move checks
        if (isKingInCheck(game, game.whiteTurn)) {
            // Revert the move
            revertMove(game, fromIndex, toIndex, moveData);
            revert("Move would leave king in check.");
        }

        // Emit move event
        emit MoveMade(gameId, msg.sender, fromIndex, toIndex);

        // Switch player
        game.whiteTurn = !game.whiteTurn;

        // Check for checkmate or stalemate
        if (checkForCheckmateOrStalemate(game, gameId)) {
            return true;
        }

        // Increment move number if black just moved
        if (!game.whiteTurn) {
            game.moveNumber++;
        }

        return true;
    }

    // Phase 1: Validation and preparation function
    function validateAndPrepareMove(
        Game storage game,
        uint8 fromIndex,
        uint8 toIndex,
        uint8 promotionChoice
    ) internal returns (MoveData memory moveData) {
        moveData.piece = game.board[fromIndex];
        require(moveData.piece != 0, "No piece at the source square.");

        // Check if it's the player's turn
        require(
            (game.whiteTurn && moveData.piece > 0) || (!game.whiteTurn && moveData.piece < 0),
            "Not your turn."
        );

        moveData.targetPiece = game.board[toIndex];

        // Validate the move
        require(validateMove(game, fromIndex, toIndex), "Invalid move.");

        // Initialize variables
        moveData.resetHalfmoveClock = false;
        moveData.isEnPassantMove = false;
        moveData.isCastlingMove = false;
        moveData.previousEnPassantTarget = game.enPassantTarget;

        // En passant capture
        if (abs(moveData.piece) == 1) {
            if (handleEnPassant(game, fromIndex, toIndex)) {
                moveData.isEnPassantMove = true;
                moveData.capturedPawnIndex = game.whiteTurn ? toIndex - 8 : toIndex + 8;
            }
        }

        // Castling
        if (abs(moveData.piece) == 6 && abs(int8(toIndex % 8) - int8(fromIndex % 8)) == 2) {
            (moveData.isCastlingMove, moveData.rookFrom, moveData.rookTo) = handleCastling(game, fromIndex, toIndex);
        }

        // Update the halfmove clock
        if (abs(moveData.piece) == 1 || moveData.targetPiece != 0 || moveData.isEnPassantMove) {
            moveData.resetHalfmoveClock = true;
        }
    }

    // Phase 2: Execution of the move
    function executeMove(
        Game storage game,
        uint8 fromIndex,
        uint8 toIndex,
        uint8 promotionChoice,
        MoveData memory moveData
    ) internal {
        // Move the piece
        game.board[toIndex] = moveData.piece;
        game.board[fromIndex] = 0;

        // Handle en passant capture
        if (moveData.isEnPassantMove) {
            game.board[moveData.capturedPawnIndex] = 0;
        }

        // Handle castling
        if (moveData.isCastlingMove) {
            game.board[moveData.rookTo] = game.board[moveData.rookFrom];
            game.board[moveData.rookFrom] = 0;
        }

        // Handle pawn promotion
        if (abs(moveData.piece) == 1 && (toIndex / 8 == 0 || toIndex / 8 == 7)) {
            handlePawnPromotion(game, toIndex, promotionChoice);
        }

        // Update castling rights
        updateCastlingRights(game, fromIndex, moveData.piece);

        // Update en passant target
        updateEnPassantTarget(game, moveData.piece, fromIndex, toIndex);

        // Update halfmove clock
        if (moveData.resetHalfmoveClock) {
            game.halfmoveClock = 0;
        } else {
            game.halfmoveClock++;
        }

        // Generate the position hash after the move
        moveData.positionHash = getPositionHash(game);
        game.positionOccurrences[moveData.positionHash]++;

        // Check for draw conditions
        if (checkForDraw(game, moveData.positionHash)) {
            finalizeGame(game.gameId);
        }
    }

    // Revert move function
    function revertMove(
        Game storage game,
        uint8 fromIndex,
        uint8 toIndex,
        MoveData memory moveData
    ) internal {
        game.board[fromIndex] = moveData.piece;
        game.board[toIndex] = moveData.targetPiece;

        // Revert en passant capture
        if (moveData.isEnPassantMove) {
            int8 capturedPawn = game.whiteTurn ? -1 : int8(1);
            game.board[moveData.capturedPawnIndex] = capturedPawn;
        }

        // Revert castling
        if (moveData.isCastlingMove) {
            game.board[moveData.rookFrom] = game.board[moveData.rookTo];
            game.board[moveData.rookTo] = 0;
        }

        // Restore en passant target
        game.enPassantTarget = moveData.previousEnPassantTarget;
    }

    // Helper functions

    function handleEnPassant(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 piece = game.board[fromIndex];
        int8 targetPiece = game.board[toIndex];
        int8 colFrom = int8(fromIndex % 8);
        int8 colTo = int8(toIndex % 8);

        if (colFrom != colTo && targetPiece == 0 && toIndex == uint8(game.enPassantTarget)) {
            return true;
        }
        return false;
    }

    function handleCastling(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool, uint8, uint8) {
        uint8 rookFrom;
        uint8 rookTo;
        if (toIndex % 8 == 6) {
            // King-side castling
            rookFrom = fromIndex + 3;
            rookTo = fromIndex + 1;
            return (true, rookFrom, rookTo);
        } else if (toIndex % 8 == 2) {
            // Queen-side castling
            rookFrom = fromIndex - 4;
            rookTo = fromIndex - 1;
            return (true, rookFrom, rookTo);
        }
        return (false, 0, 0);
    }

    function handlePawnPromotion(Game storage game, uint8 toIndex, uint8 promotionChoice) internal {
        require(promotionChoice >= 2 && promotionChoice <= 5, "Invalid promotion choice.");
        game.board[toIndex] = int8(game.whiteTurn ? int8(promotionChoice) : -1 * int8(promotionChoice));
    }

    function updateCastlingRights(Game storage game, uint8 fromIndex, int8 piece) internal {
        if (abs(piece) == 6) {
            if (game.whiteTurn) {
                game.whiteKingMoved = true;
            } else {
                game.blackKingMoved = true;
            }
        }
        if (abs(piece) == 4) {
            if (fromIndex % 8 == 0) {
                // Queen-side rook moved
                if (game.whiteTurn) {
                    game.whiteRookQueenSideMoved = true;
                } else {
                    game.blackRookQueenSideMoved = true;
                }
            } else if (fromIndex % 8 == 7) {
                // King-side rook moved
                if (game.whiteTurn) {
                    game.whiteRookKingSideMoved = true;
                } else {
                    game.blackRookKingSideMoved = true;
                }
            }
        }
    }

    function updateEnPassantTarget(Game storage game, int8 piece, uint8 fromIndex, uint8 toIndex) internal {
        if (abs(piece) == 1 && abs(int8(toIndex) - int8(fromIndex)) == 16) {
            game.enPassantTarget = int8((fromIndex + toIndex) / 2);
        } else {
            game.enPassantTarget = -1;
        }
    }


    function checkForDraw(Game storage game, bytes32 positionHash) internal returns (bool) {
        // Threefold repetition
        if (game.positionOccurrences[positionHash] >= 3) {
            game.gameState = GameState.Draw;
            return true;
        }

        // Insufficient material
        if (isInsufficientMaterial(game)) {
            game.gameState = GameState.Draw;
            return true;
        }

        // 50-move rule
        if (game.halfmoveClock >= 100) {
            game.gameState = GameState.Draw;
            return true;
        }

        return false;
    }

    function checkForCheckmateOrStalemate(Game storage game, uint256 gameId) internal returns (bool) {
        if (isKingInCheck(game, game.whiteTurn) && !hasLegalMoves(game, game.whiteTurn)) {
            game.gameState = game.whiteTurn ? GameState.BlackWon : GameState.WhiteWon;
            finalizeGame(gameId);
            return true;
        }

        if (!isKingInCheck(game, game.whiteTurn) && !hasLegalMoves(game, game.whiteTurn)) {
            game.gameState = GameState.Draw;
            finalizeGame(gameId);
            return true;
        }

        return false;
    }

    // Finalize the game and transfer keys
    function finalizeGame(uint256 gameId) internal {
        Game storage game = games[gameId];
        game.gameState = GameState.Ended;
        spareGameId = gameId;

        if (game.gameState == GameState.WhiteWon) {
            // Transfer both keys to the winner
            IERC721(keyContract).transferFrom(address(this), game.playerWhite, game.keyWhite);
            IERC721(keyContract).transferFrom(address(this), game.playerWhite, game.keyBlack);
        } else if (game.gameState == GameState.BlackWon) {
            // Transfer both keys to the winner
            IERC721(keyContract).transferFrom(address(this), game.playerBlack, game.keyWhite);
            IERC721(keyContract).transferFrom(address(this), game.playerBlack, game.keyBlack);
        } else if (game.gameState == GameState.Draw) {
            // Return keys to respective players
            IERC721(keyContract).transferFrom(address(this), game.playerWhite, game.keyWhite);
            IERC721(keyContract).transferFrom(address(this), game.playerBlack, game.keyBlack);
        }

        emit GameEnded(gameId, game.gameState);
    }

    // Move validation function
    function validateMove(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 piece = game.board[fromIndex];
        int8 targetPiece = game.board[toIndex];

        // Ensure destination is not occupied by own piece
        if (game.whiteTurn) {
            if (targetPiece > 0) return false;
        } else {
            if (targetPiece < 0) return false;
        }

        if (abs(piece) == 1) {
            return validatePawnMove(game, fromIndex, toIndex);
        } else if (abs(piece) == 2) {
            return validateKnightMove(fromIndex, toIndex);
        } else if (abs(piece) == 3) {
            return validateBishopMove(game, fromIndex, toIndex);
        } else if (abs(piece) == 4) {
            return validateRookMove(game, fromIndex, toIndex);
        } else if (abs(piece) == 5) {
            return validateQueenMove(game, fromIndex, toIndex);
        } else if (abs(piece) == 6) {
            return validateKingMove(game, fromIndex, toIndex);
        }

        return false;
    }

    function validatePawnMove(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 direction = game.whiteTurn ? int8(1) : -1;
        int8 rowFrom = int8(fromIndex / 8);
        int8 rowTo = int8(toIndex / 8);
        int8 colFrom = int8(fromIndex % 8);
        int8 colTo = int8(toIndex % 8);

        int8 targetPiece = game.board[toIndex];

        // Moving forward
        if (colFrom == colTo) {
            if (targetPiece != 0) return false;
            if (rowTo == rowFrom + direction) {
                return true;
            }
            // Double move from starting position
            if ((game.whiteTurn && rowFrom == 1) || (!game.whiteTurn && rowFrom == 6)) {
                if (rowTo == rowFrom + 2 * direction) {
                    // Ensure intermediate square is empty
                    uint8 intermediateIndex = uint8(int8(fromIndex) + 8 * direction);
                    if (game.board[intermediateIndex] == 0 && targetPiece == 0) {
                        return true;
                    }
                }
            }
        } else if (abs(colTo - colFrom) == 1 && rowTo == rowFrom + direction) {
            // Capturing
            if (game.whiteTurn && targetPiece < 0) {
                return true;
            } else if (!game.whiteTurn && targetPiece > 0) {
                return true;
            }
            // En passant
            if (toIndex == uint8(game.enPassantTarget)) {
                return true;
            }
        }

        return false;
    }

    function validateKnightMove(uint8 fromIndex, uint8 toIndex) internal pure returns (bool) {
        int8 rowDiff = abs(int8(toIndex / 8) - int8(fromIndex / 8));
        int8 colDiff = abs(int8(toIndex % 8) - int8(fromIndex % 8));

        return (rowDiff == 2 && colDiff == 1) || (rowDiff == 1 && colDiff == 2);
    }

    function validateBishopMove(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        return validateDiagonalMove(game, fromIndex, toIndex);
    }

    function validateRookMove(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        return validateStraightMove(game, fromIndex, toIndex);
    }

    function validateQueenMove(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        return validateStraightMove(game, fromIndex, toIndex) || validateDiagonalMove(game, fromIndex, toIndex);
    }

    function validateKingMove(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 rowFrom = int8(fromIndex / 8);
        int8 rowTo = int8(toIndex / 8);
        int8 colFrom = int8(fromIndex % 8);
        int8 colTo = int8(toIndex % 8);

        int8 rowDiff = abs(rowTo - rowFrom);
        int8 colDiff = abs(colTo - colFrom);

        // Normal king move
        if (rowDiff <= 1 && colDiff <= 1) {
            return true;
        }

        // Castling
        if (rowFrom == rowTo && !hasKingMoved(game, game.whiteTurn)) {
            // King-side castling
            if (colTo - colFrom == 2 && !hasRookMoved(game, game.whiteTurn, true)) {
                if (game.board[fromIndex + 1] == 0 && game.board[fromIndex + 2] == 0) {
                    // Additional checks for check need to be added
                    return true;
                }
            }
            // Queen-side castling
            if (colFrom - colTo == 2 && !hasRookMoved(game, game.whiteTurn, false)) {
                if (game.board[fromIndex - 1] == 0 && game.board[fromIndex - 2] == 0 && game.board[fromIndex - 3] == 0) {
                    // Additional checks for check need to be added
                    return true;
                }
            }
        }

        return false;
    }

    function hasKingMoved(Game storage game, bool isWhite) internal view returns (bool) {
        return isWhite ? game.whiteKingMoved : game.blackKingMoved;
    }

    function hasRookMoved(Game storage game, bool isWhite, bool kingSide) internal view returns (bool) {
        if (isWhite) {
            return kingSide ? game.whiteRookKingSideMoved : game.whiteRookQueenSideMoved;
        } else {
            return kingSide ? game.blackRookKingSideMoved : game.blackRookQueenSideMoved;
        }
    }

    function validateStraightMove(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 rowDiff = int8(toIndex / 8) - int8(fromIndex / 8);
        int8 colDiff = int8(toIndex % 8) - int8(fromIndex % 8);

        if (rowDiff != 0 && colDiff != 0) return false;

        int8 rowStep = rowDiff != 0 ? rowDiff / abs(rowDiff) : int8(0);
        int8 colStep = colDiff != 0 ? colDiff / abs(colDiff) : int8(0);

        return pathIsClear(game, fromIndex, toIndex, rowStep, colStep);
    }

    function validateDiagonalMove(Game storage game, uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 rowDiff = int8(toIndex / 8) - int8(fromIndex / 8);
        int8 colDiff = int8(toIndex % 8) - int8(fromIndex % 8);

        if (abs(rowDiff) != abs(colDiff)) return false;

        int8 rowStep = rowDiff / abs(rowDiff);
        int8 colStep = colDiff / abs(colDiff);

        return pathIsClear(game, fromIndex, toIndex, rowStep, colStep);
    }

    function pathIsClear(Game storage game, uint8 fromIndex, uint8 toIndex, int8 rowStep, int8 colStep) internal view returns (bool) {
        int8 rowFrom = int8(fromIndex / 8) + rowStep;
        int8 colFrom = int8(fromIndex % 8) + colStep;
        int8 rowTo = int8(toIndex / 8);
        int8 colTo = int8(toIndex % 8);

        while (rowFrom != rowTo || colFrom != colTo) {
            if (game.board[uint8(rowFrom * 8 + colFrom)] != 0) {
                return false;
            }
            rowFrom += rowStep;
            colFrom += colStep;
        }
        return true;
    }

    function isKingInCheck(Game storage game, bool isWhite) internal view returns (bool) {
        int8 player = isWhite ? int8(1) : -1;
        uint8 kingIndex = 64;
        for (uint8 i = 0; i < 64; i++) {
            if (game.board[i] == 6 * player) {
                kingIndex = i;
                break;
            }
        }
        require(kingIndex < 64, "King not found on the board.");

        for (uint8 i = 0; i < 64; i++) {
            if (game.board[i] * player < 0) {
                if (validateMoveForCheck(game, i, kingIndex, !isWhite)) {
                    return true;
                }
            }
        }

        return false;
    }

    function hasLegalMoves(Game storage game, bool isWhite) internal returns (bool) {
        int8 player = isWhite ? int8(1) : -1;
        for (uint8 fromIndex = 0; fromIndex < 64; fromIndex++) {
            if (game.board[fromIndex] * player <= 0) continue;

            for (uint8 toIndex = 0; toIndex < 64; toIndex++) {
                if (game.board[toIndex] * player > 0) continue;

                if (validateMove(game, fromIndex, toIndex)) {
                    // Simulate the move
                    int8 piece = game.board[fromIndex];
                    int8 targetPiece = game.board[toIndex];
                    game.board[toIndex] = piece;
                    game.board[fromIndex] = 0;

                    bool kingSafe = !isKingInCheck(game, isWhite);

                    // Revert the move
                    game.board[fromIndex] = piece;
                    game.board[toIndex] = targetPiece;

                    if (kingSafe) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    function validateMoveForCheck(Game storage game, uint8 fromIndex, uint8 toIndex, bool isWhite) internal view returns (bool) {
        int8 piece = game.board[fromIndex];
        int8 player = isWhite ? int8(1) : -1;
        if (piece * player <= 0) return false;
        int8 targetPiece = game.board[toIndex];
        if (targetPiece * player > 0) return false;

        if (abs(piece) == 1) {
            return validatePawnMoveForCheck(game, fromIndex, toIndex, isWhite);
        } else if (abs(piece) == 2) {
            return validateKnightMove(fromIndex, toIndex);
        } else if (abs(piece) == 3) {
            return validateDiagonalMove(game, fromIndex, toIndex);
        } else if (abs(piece) == 4) {
            return validateStraightMove(game, fromIndex, toIndex);
        } else if (abs(piece) == 5) {
            return validateStraightMove(game, fromIndex, toIndex) || validateDiagonalMove(game, fromIndex, toIndex);
        } else if (abs(piece) == 6) {
            return validateKingMoveForCheck(fromIndex, toIndex);
        }

        return false;
    }

    function validatePawnMoveForCheck(Game storage game, uint8 fromIndex, uint8 toIndex, bool isWhite) internal pure returns (bool) {
        int8 direction = isWhite ? int8(1) : -1;
        int8 rowFrom = int8(fromIndex / 8);
        int8 rowTo = int8(toIndex / 8);
        int8 colFrom = int8(fromIndex % 8);
        int8 colTo = int8(toIndex % 8);

        if (abs(colTo - colFrom) == 1 && rowTo == rowFrom + direction) {
            return true;
        }

        return false;
    }

    function validateKingMoveForCheck(uint8 fromIndex, uint8 toIndex) internal pure returns (bool) {
        int8 rowDiff = abs(int8(toIndex / 8) - int8(fromIndex / 8));
        int8 colDiff = abs(int8(toIndex % 8) - int8(fromIndex % 8));

        return rowDiff <= 1 && colDiff <= 1;
    }

    function isInsufficientMaterial(Game storage game) internal view returns (bool) {
        uint8 whitePieces;
        uint8 blackPieces;
        uint8 whiteBishops;
        uint8 blackBishops;
        uint8 whiteKnights;
        uint8 blackKnights;

        for (uint8 i = 0; i < 64; i++) {
            int8 piece = game.board[i];
            if (piece == 0) continue;

            int8 absPiece = abs(piece);

            if (piece > 0) {
                if (absPiece == 1 || absPiece == 4 || absPiece == 5) return false;
                if (absPiece == 3) whiteBishops++;
                if (absPiece == 2) whiteKnights++;
                whitePieces++;
            } else {
                if (absPiece == 1 || absPiece == 4 || absPiece == 5) return false;
                if (absPiece == 3) blackBishops++;
                if (absPiece == 2) blackKnights++;
                blackPieces++;
            }
        }

        if (whitePieces == 1 && blackPieces == 1) {
            return true;
        }

        if ((whitePieces == 2 && blackPieces == 1) || (whitePieces == 1 && blackPieces == 2)) {
            if ((whiteBishops == 1 || whiteKnights == 1) || (blackBishops == 1 || blackKnights == 1)) {
                return true;
            }
        }

        if (whitePieces == 2 && blackPieces == 2 && whiteBishops == 1 && blackBishops == 1) {
            return true;
        }

        return false;
    }

    function getPositionHash(Game storage game) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            game.board,
            game.whiteTurn,
            game.enPassantTarget,
            game.whiteKingMoved,
            game.whiteRookKingSideMoved,
            game.whiteRookQueenSideMoved,
            game.blackKingMoved,
            game.blackRookKingSideMoved,
            game.blackRookQueenSideMoved
        ));
    }

    function abs(int8 x) internal pure returns (int8) {
        return x >= 0 ? x : -x;
    }

    // Owner only setters for game parameters
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
}