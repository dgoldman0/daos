// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ChessGame {
    // Board representation as a 64-element array
    int8[64] public board;
    
    // Tracks the current player (1 for white, -1 for black)
    int8 public currentPlayer;
    
    // Castling rights
    bool public whiteKingMoved = false;
    bool public whiteRookKingSideMoved = false;
    bool public whiteRookQueenSideMoved = false;
    bool public blackKingMoved = false;
    bool public blackRookKingSideMoved = false;
    bool public blackRookQueenSideMoved = false;

    // En passant target square index (-1 if not available)
    int8 public enPassantTarget = -1;

    // Halfmove clock for the 50-move rule
    uint256 public halfmoveClock = 0;

    // Mapping from position hash to occurrence count (for threefold repetition)
    mapping(bytes32 => uint8) public positionOccurrences;

    // Game state enum
    enum GameState { Active, WhiteWon, BlackWon, Draw }
    GameState public gameState = GameState.Active;

    // Move number
    uint256 public moveNumber = 1;

    // Constructor to initialize the board to the standard starting position
    constructor() {
        initializeBoard();
        currentPlayer = 1;  // White starts
    }

    // Initialize board to standard chess starting position
    function initializeBoard() internal {
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

    // Move function with promotion and special move handling (en passant, castling)
    function move(uint8 fromIndex, uint8 toIndex, uint8 promotionChoice) public returns (bool) {
        require(gameState == GameState.Active, "The game has ended.");
        require(fromIndex < 64 && toIndex < 64, "Invalid index, must be within 0 and 63.");
        require(board[fromIndex] * currentPlayer > 0, "You can only move your own pieces.");

        int8 piece = board[fromIndex];
        int8 targetPiece = board[toIndex];

        // Validate move
        require(validateMove(fromIndex, toIndex), "Invalid move.");

        // Determine if the halfmove clock should reset
        bool resetHalfmoveClock = false;
        if (abs(piece) == 1) {
            resetHalfmoveClock = true; // Pawn move
        }
        if (targetPiece != 0) {
            resetHalfmoveClock = true; // Capture
        }

        // En passant logic
        if (piece == 1 * currentPlayer) {
            int8 colFrom = int8(fromIndex % 8);
            int8 colTo = int8(toIndex % 8);

            if (colFrom != colTo && targetPiece == 0 && toIndex == uint8(enPassantTarget)) {
                uint8 capturedPawnIndex = currentPlayer == 1 ? toIndex - 8 : toIndex + 8;
                board[capturedPawnIndex] = 0; // Remove the captured pawn
            }
        }

        // Castling logic
        if (piece == 6 * currentPlayer) {
            if (abs(int8(toIndex % 8) - int8(fromIndex % 8)) == 2) {
                // Castling
                if (toIndex % 8 == 6) {
                    // King-side castling
                    uint8 rookFrom = fromIndex + 3;
                    uint8 rookTo = fromIndex + 1;
                    board[rookTo] = board[rookFrom];
                    board[rookFrom] = 0;
                } else if (toIndex % 8 == 2) {
                    // Queen-side castling
                    uint8 rookFrom = fromIndex - 4;
                    uint8 rookTo = fromIndex - 1;
                    board[rookTo] = board[rookFrom];
                    board[rookFrom] = 0;
                }

                // Update castling rights
                if (currentPlayer == 1) {
                    whiteKingMoved = true;
                } else {
                    blackKingMoved = true;
                }
            }
        }

        // Move the piece
        board[toIndex] = piece;
        board[fromIndex] = 0;

        // Handle pawn promotion
        if (piece == 1 * currentPlayer && (toIndex / 8 == 0 || toIndex / 8 == 7)) {
            require(promotionChoice >= 2 && promotionChoice <= 5, "Invalid promotion choice.");
            board[toIndex] = int8(promotionChoice) * currentPlayer;
        }

        // Update en passant target
        if (piece == 1 * currentPlayer && abs(int8(toIndex) - int8(fromIndex)) == 16) {
            enPassantTarget = int8((fromIndex + toIndex) / 2);
        } else {
            enPassantTarget = -1;
        }

        // Update halfmove clock
        if (resetHalfmoveClock) {
            halfmoveClock = 0;
        } else {
            halfmoveClock++;
        }

        // Generate the position hash after the move
        bytes32 positionHash = getPositionHash();

        // Update the position occurrences
        positionOccurrences[positionHash]++;

        // Check for threefold repetition
        if (positionOccurrences[positionHash] >= 3) {
            gameState = GameState.Draw;
            return true;
        }

        // Check for insufficient material
        if (isInsufficientMaterial()) {
            gameState = GameState.Draw;
            return true;
        }

        // Check for 50-move rule
        if (halfmoveClock >= 100) {
            gameState = GameState.Draw;
            return true;
        }

        // Switch player
        currentPlayer *= -1;

        // Check for stalemate
        if (isStalemate(currentPlayer)) {
            gameState = GameState.Draw;
            return true;
        }

        // Check for checkmate
        if (isKingInCheck(currentPlayer) && !hasLegalMoves(currentPlayer)) {
            gameState = currentPlayer == 1 ? GameState.BlackWon : GameState.WhiteWon;
            return true;
        }

        return true;
    }

    // Utility function to calculate absolute value
    function abs(int8 x) internal pure returns (int8) {
        return x >= 0 ? x : -x;
    }

    // Position hashing for threefold repetition
    function getPositionHash() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            board,
            currentPlayer,
            enPassantTarget,
            whiteKingMoved,
            whiteRookKingSideMoved,
            whiteRookQueenSideMoved,
            blackKingMoved,
            blackRookKingSideMoved,
            blackRookQueenSideMoved
        ));
    }

    // Insufficient material detection
    function isInsufficientMaterial() internal view returns (bool) {
        uint8 whitePieces;
        uint8 blackPieces;
        uint8 whiteBishops;
        uint8 blackBishops;
        uint8 whiteKnights;
        uint8 blackKnights;

        for (uint8 i = 0; i < 64; i++) {
            int8 piece = board[i];
            if (piece == 0) continue;

            int8 absPiece = abs(piece);

            if (piece > 0) {
                if (absPiece == 1 || absPiece == 4 || absPiece == 5) return false; // Pawn, Rook, Queen
                if (absPiece == 3) whiteBishops++;
                if (absPiece == 2) whiteKnights++;
                whitePieces++;
            } else {
                if (absPiece == 1 || absPiece == 4 || absPiece == 5) return false; // Pawn, Rook, Queen
                if (absPiece == 3) blackBishops++;
                if (absPiece == 2) blackKnights++;
                blackPieces++;
            }
        }

        // Only kings left
        if (whitePieces == 1 && blackPieces == 1) {
            return true;
        }

        // King and Bishop or Knight vs. King
        if ((whitePieces == 2 && blackPieces == 1) || (whitePieces == 1 && blackPieces == 2)) {
            if ((whiteBishops == 1 || whiteKnights == 1) || (blackBishops == 1 || blackKnights == 1)) {
                return true;
            }
        }

        // King and Bishop vs. King and Bishop (same color bishops)
        if (whitePieces == 2 && blackPieces == 2 && whiteBishops == 1 && blackBishops == 1) {
            return true;
        }

        return false;
    }

    // Check if the player's king is in check
    function isKingInCheck(int8 player) internal view returns (bool) {
        uint8 kingIndex = 64;
        for (uint8 i = 0; i < 64; i++) {
            if (board[i] == 6 * player) {
                kingIndex = i;
                break;
            }
        }
        require(kingIndex < 64, "King not found on the board.");

        for (uint8 i = 0; i < 64; i++) {
            if (board[i] * player < 0) {
                if (validateMoveForCheck(i, kingIndex, -player)) {
                    return true;
                }
            }
        }

        return false;
    }

    // Stalemate detection
    function isStalemate(int8 player) internal returns (bool) {
        if (isKingInCheck(player)) {
            return false;
        }
        return !hasLegalMoves(player);
    }

    // Legal move detection
    function hasLegalMoves(int8 player) internal returns (bool) {
        for (uint8 fromIndex = 0; fromIndex < 64; fromIndex++) {
            if (board[fromIndex] * player <= 0) continue;

            for (uint8 toIndex = 0; toIndex < 64; toIndex++) {
                if (board[toIndex] * player > 0) continue;

                int8 piece = board[fromIndex];
                int8 targetPiece = board[toIndex];

                if (validateMoveForCheck(fromIndex, toIndex, player)) {
                    board[toIndex] = piece;
                    board[fromIndex] = 0;

                    bool kingSafe = !isKingInCheck(player);

                    board[fromIndex] = piece;
                    board[toIndex] = targetPiece;

                    if (kingSafe) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    // Check if a move is valid for checking purposes (simplified for check detection)
    function validateMoveForCheck(uint8 fromIndex, uint8 toIndex, int8 player) internal view returns (bool) {
        int8 piece = board[fromIndex];
        if (piece * player <= 0) return false;
        int8 targetPiece = board[toIndex];
        if (targetPiece * player > 0) return false;

        if (abs(piece) == 1) {
            int8 direction = player == 1 ? 1 : -1;
            int8 rowFrom = int8(fromIndex / 8);
            int8 rowTo = int8(toIndex / 8);
            int8 colFrom = int8(fromIndex % 8);
            int8 colTo = int8(toIndex % 8);
            if (rowTo == rowFrom + direction && (colTo == colFrom + 1 || colTo == colFrom - 1)) {
                return true;
            }
        } else if (abs(piece) == 2) {
            return validateKnightMove(fromIndex, toIndex);
        } else if (abs(piece) == 3) {
            return validateDiagonalMove(fromIndex, toIndex);
        } else if (abs(piece) == 4) {
            return validateStraightMove(fromIndex, toIndex);
        } else if (abs(piece) == 5) {
            return validateQueenMove(fromIndex, toIndex);
        } else if (abs(piece) == 6) {
            int8 rowDiff = int8(toIndex / 8) - int8(fromIndex / 8);
            int8 colDiff = int8(toIndex % 8) - int8(fromIndex % 8);
            if (abs(rowDiff) <= 1 && abs(colDiff) <= 1) {
                return true;
            }
        }

        return false;
    }

    // Straight move validation (Rook, Queen movement)
    function validateStraightMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 rowDiff = int8(toIndex / 8) - int8(fromIndex / 8);
        int8 colDiff = int8(toIndex % 8) - int8(fromIndex % 8);

        if (rowDiff != 0 && colDiff != 0) return false;

        int8 rowStep = rowDiff != 0 ? rowDiff / abs(rowDiff) : 0;
        int8 colStep = colDiff != 0 ? colDiff / abs(colDiff) : 0;

        return pathIsClear(fromIndex, toIndex, rowStep, colStep);
    }

    // Diagonal move validation (Bishop, Queen movement)
    function validateDiagonalMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 rowDiff = int8(toIndex / 8) - int8(fromIndex / 8);
        int8 colDiff = int8(toIndex % 8) - int8(fromIndex % 8);

        if (abs(rowDiff) != abs(colDiff)) return false;

        int8 rowStep = rowDiff / abs(rowDiff);
        int8 colStep = colDiff / abs(colDiff);

        return pathIsClear(fromIndex, toIndex, rowStep, colStep);
    }

    // Knight move validation
    function validateKnightMove(uint8 fromIndex, uint8 toIndex) internal pure returns (bool) {
        int8 rowDiff = int8(toIndex / 8) - int8(fromIndex / 8);
        int8 colDiff = int8(toIndex % 8) - int8(fromIndex % 8);

        return (abs(rowDiff) == 2 && abs(colDiff) == 1) || (abs(rowDiff) == 1 && abs(colDiff) == 2);
    }

    // Validate path for clear movement (straight and diagonal)
    function pathIsClear(uint8 fromIndex, uint8 toIndex, int8 rowStep, int8 colStep) internal view returns (bool) {
        int8 rowFrom = int8(fromIndex / 8);
        int8 colFrom = int8(fromIndex % 8);
        int8 rowTo = int8(toIndex / 8);
        int8 colTo = int8(toIndex % 8);

        rowFrom += rowStep;
        colFrom += colStep;

        while (rowFrom != rowTo || colFrom != colTo) {
            if (board[uint8(rowFrom * 8 + colFrom)] != 0) {
                return false;
            }
            rowFrom += rowStep;
            colFrom += colStep;
        }

        return true;
    }
}
