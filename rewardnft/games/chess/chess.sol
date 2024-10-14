// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ChessGame {
    int8[64] public board;
    bool public whiteTurn; // true for White's turn, false for Black's turn

    // Castling rights
    bool public whiteKingMoved = false;
    bool public whiteRookKingSideMoved = false;
    bool public whiteRookQueenSideMoved = false;
    bool public blackKingMoved = false;
    bool public blackRookKingSideMoved = false;
    bool public blackRookQueenSideMoved = false;

    int8 public enPassantTarget = -1; // Square index (-1 if not available)
    uint256 public halfmoveClock = 0;
    mapping(bytes32 => uint8) public positionOccurrences;
    enum GameState { Active, WhiteWon, BlackWon, Draw }
    GameState public gameState = GameState.Active;
    uint256 public moveNumber = 1;

    constructor() {
        initializeBoard();
        whiteTurn = true;  // White starts
    }

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

    function move(uint8 fromIndex, uint8 toIndex, uint8 promotionChoice) public returns (bool) {
        require(gameState == GameState.Active, "The game has ended.");
        require(fromIndex < 64 && toIndex < 64, "Invalid index.");
        int8 piece = board[fromIndex];
        require(piece != 0, "No piece at the source square.");

        // Check if it's the player's turn
        if (whiteTurn) {
            require(piece > 0, "It's White's turn.");
        } else {
            require(piece < 0, "It's Black's turn.");
        }

        int8 targetPiece = board[toIndex];
        require(validateMove(fromIndex, toIndex), "Invalid move.");

        bool resetHalfmoveClock = false;
        if (abs(piece) == 1) {
            resetHalfmoveClock = true;
        }
        if (targetPiece != 0) {
            resetHalfmoveClock = true;
        }

        // En passant capture
        if (abs(piece) == 1) {
            int8 colFrom = int8(fromIndex % 8);
            int8 colTo = int8(toIndex % 8);
            if (colFrom != colTo && targetPiece == 0 && toIndex == uint8(enPassantTarget)) {
                uint8 capturedPawnIndex = whiteTurn ? toIndex - 8 : toIndex + 8;
                board[capturedPawnIndex] = 0;
            }
        }

        // Castling
        if (abs(piece) == 6 && abs(int8(toIndex % 8) - int8(fromIndex % 8)) == 2) {
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
        }

        // Move the piece
        board[toIndex] = piece;
        board[fromIndex] = 0;

        // Update castling rights
        if (abs(piece) == 6) {
            if (whiteTurn) {
                whiteKingMoved = true;
            } else {
                blackKingMoved = true;
            }
        }
        if (abs(piece) == 4) {
            if (fromIndex % 8 == 0) {
                // Queen-side rook moved
                if (whiteTurn) {
                    whiteRookQueenSideMoved = true;
                } else {
                    blackRookQueenSideMoved = true;
                }
            } else if (fromIndex % 8 == 7) {
                // King-side rook moved
                if (whiteTurn) {
                    whiteRookKingSideMoved = true;
                } else {
                    blackRookKingSideMoved = true;
                }
            }
        }

        // Handle pawn promotion
        if (abs(piece) == 1 && (toIndex / 8 == 0 || toIndex / 8 == 7)) {
            require(promotionChoice >= 2 && promotionChoice <= 5, "Invalid promotion choice.");
            board[toIndex] = int8(whiteTurn ? promotionChoice : -promotionChoice);
        }

        // Update en passant target
        if (abs(piece) == 1 && abs(int8(toIndex) - int8(fromIndex)) == 16) {
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

        // Check if the player's own king is in check after the move
        if (isKingInCheck(whiteTurn)) {
            // Revert the move
            board[fromIndex] = piece;
            board[toIndex] = targetPiece;
            // Revert castling if applicable
            if (abs(piece) == 6 && abs(int8(toIndex % 8) - int8(fromIndex % 8)) == 2) {
                if (toIndex % 8 == 6) {
                    // King-side castling
                    uint8 rookFrom = fromIndex + 3;
                    uint8 rookTo = fromIndex + 1;
                    board[rookFrom] = board[rookTo];
                    board[rookTo] = 0;
                } else if (toIndex % 8 == 2) {
                    // Queen-side castling
                    uint8 rookFrom = fromIndex - 4;
                    uint8 rookTo = fromIndex - 1;
                    board[rookFrom] = board[rookTo];
                    board[rookTo] = 0;
                }
            }
            revert("Move would leave king in check.");
        }

        // Switch player
        whiteTurn = !whiteTurn;

        // Check for checkmate
        if (isKingInCheck(whiteTurn) && !hasLegalMoves(whiteTurn)) {
            gameState = whiteTurn ? GameState.BlackWon : GameState.WhiteWon;
            return true;
        }

        // Check for stalemate
        if (!isKingInCheck(whiteTurn) && !hasLegalMoves(whiteTurn)) {
            gameState = GameState.Draw;
            return true;
        }

        return true;
    }

    // Move validation function
    function validateMove(uint8 fromIndex, uint8 toIndex) public view returns (bool) {
        int8 piece = board[fromIndex];
        int8 targetPiece = board[toIndex];

        // Ensure destination is not occupied by own piece
        if (whiteTurn) {
            if (targetPiece > 0) return false;
        } else {
            if (targetPiece < 0) return false;
        }

        if (abs(piece) == 1) {
            return validatePawnMove(fromIndex, toIndex);
        } else if (abs(piece) == 2) {
            return validateKnightMove(fromIndex, toIndex);
        } else if (abs(piece) == 3) {
            return validateBishopMove(fromIndex, toIndex);
        } else if (abs(piece) == 4) {
            return validateRookMove(fromIndex, toIndex);
        } else if (abs(piece) == 5) {
            return validateQueenMove(fromIndex, toIndex);
        } else if (abs(piece) == 6) {
            return validateKingMove(fromIndex, toIndex);
        }

        return false;
    }

    function validatePawnMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 direction = whiteTurn ? 1 : -1;
        int8 rowFrom = int8(fromIndex / 8);
        int8 rowTo = int8(toIndex / 8);
        int8 colFrom = int8(fromIndex % 8);
        int8 colTo = int8(toIndex % 8);

        int8 targetPiece = board[toIndex];

        // Moving forward
        if (colFrom == colTo) {
            if (targetPiece != 0) return false;
            if (rowTo == rowFrom + direction) {
                return true;
            }
            // Double move from starting position
            if ((whiteTurn && rowFrom == 1) || (!whiteTurn && rowFrom == 6)) {
                if (rowTo == rowFrom + 2 * direction) {
                    // Ensure intermediate square is empty
                    uint8 intermediateIndex = uint8(int8(fromIndex) + 8 * direction);
                    if (board[intermediateIndex] == 0 && targetPiece == 0) {
                        return true;
                    }
                }
            }
        } else if (abs(colTo - colFrom) == 1 && rowTo == rowFrom + direction) {
            // Capturing
            if (whiteTurn && targetPiece < 0) {
                return true;
            } else if (!whiteTurn && targetPiece > 0) {
                return true;
            }
            // En passant
            if (toIndex == uint8(enPassantTarget)) {
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

    function validateBishopMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        return validateDiagonalMove(fromIndex, toIndex);
    }

    function validateRookMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        return validateStraightMove(fromIndex, toIndex);
    }

    function validateQueenMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        return validateStraightMove(fromIndex, toIndex) || validateDiagonalMove(fromIndex, toIndex);
    }

    function validateKingMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
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
        if (rowFrom == rowTo && !hasKingMoved(whiteTurn)) {
            // King-side castling
            if (colTo - colFrom == 2 && !hasRookMoved(whiteTurn, true)) {
                if (board[fromIndex + 1] == 0 && board[fromIndex + 2] == 0) {
                    // Additional checks for check need to be added
                    return true;
                }
            }
            // Queen-side castling
            if (colFrom - colTo == 2 && !hasRookMoved(whiteTurn, false)) {
                if (board[fromIndex - 1] == 0 && board[fromIndex - 2] == 0 && board[fromIndex - 3] == 0) {
                    // Additional checks for check need to be added
                    return true;
                }
            }
        }

        return false;
    }

    function hasKingMoved(bool isWhite) internal view returns (bool) {
        return isWhite ? whiteKingMoved : blackKingMoved;
    }

    function hasRookMoved(bool isWhite, bool kingSide) internal view returns (bool) {
        if (isWhite) {
            return kingSide ? whiteRookKingSideMoved : whiteRookQueenSideMoved;
        } else {
            return kingSide ? blackRookKingSideMoved : blackRookQueenSideMoved;
        }
    }

    function validateStraightMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 rowDiff = int8(toIndex / 8) - int8(fromIndex / 8);
        int8 colDiff = int8(toIndex % 8) - int8(fromIndex % 8);

        if (rowDiff != 0 && colDiff != 0) return false;

        int8 rowStep = rowDiff != 0 ? rowDiff / abs(rowDiff) : 0;
        int8 colStep = colDiff != 0 ? colDiff / abs(colDiff) : 0;

        return pathIsClear(fromIndex, toIndex, rowStep, colStep);
    }

    function validateDiagonalMove(uint8 fromIndex, uint8 toIndex) internal view returns (bool) {
        int8 rowDiff = int8(toIndex / 8) - int8(fromIndex / 8);
        int8 colDiff = int8(toIndex % 8) - int8(fromIndex % 8);

        if (abs(rowDiff) != abs(colDiff)) return false;

        int8 rowStep = rowDiff / abs(rowDiff);
        int8 colStep = colDiff / abs(colDiff);

        return pathIsClear(fromIndex, toIndex, rowStep, colStep);
    }

    function pathIsClear(uint8 fromIndex, uint8 toIndex, int8 rowStep, int8 colStep) internal view returns (bool) {
        int8 rowFrom = int8(fromIndex / 8) + rowStep;
        int8 colFrom = int8(fromIndex % 8) + colStep;
        int8 rowTo = int8(toIndex / 8);
        int8 colTo = int8(toIndex % 8);

        while (rowFrom != rowTo || colFrom != colTo) {
            if (board[uint8(rowFrom * 8 + colFrom)] != 0) {
                return false;
            }
            rowFrom += rowStep;
            colFrom += colStep;
        }
        return true;
    }

    function isKingInCheck(bool isWhite) internal view returns (bool) {
        int8 player = isWhite ? 1 : -1;
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
                if (validateMoveForCheck(i, kingIndex, !isWhite)) {
                    return true;
                }
            }
        }

        return false;
    }

    function hasLegalMoves(bool isWhite) internal returns (bool) {
        int8 player = isWhite ? 1 : -1;
        for (uint8 fromIndex = 0; fromIndex < 64; fromIndex++) {
            if (board[fromIndex] * player <= 0) continue;

            for (uint8 toIndex = 0; toIndex < 64; toIndex++) {
                if (board[toIndex] * player > 0) continue;

                int8 piece = board[fromIndex];
                int8 targetPiece = board[toIndex];

                if (validateMoveForCheck(fromIndex, toIndex, isWhite)) {
                    // Simulate the move
                    board[toIndex] = piece;
                    board[fromIndex] = 0;

                    bool kingSafe = !isKingInCheck(isWhite);

                    // Revert the move
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

    function validateMoveForCheck(uint8 fromIndex, uint8 toIndex, bool isWhite) internal view returns (bool) {
        int8 piece = board[fromIndex];
        int8 player = isWhite ? 1 : -1;
        if (piece * player <= 0) return false;
        int8 targetPiece = board[toIndex];
        if (targetPiece * player > 0) return false;

        if (abs(piece) == 1) {
            return validatePawnMoveForCheck(fromIndex, toIndex, isWhite);
        } else if (abs(piece) == 2) {
            return validateKnightMove(fromIndex, toIndex);
        } else if (abs(piece) == 3) {
            return validateDiagonalMove(fromIndex, toIndex);
        } else if (abs(piece) == 4) {
            return validateStraightMove(fromIndex, toIndex);
        } else if (abs(piece) == 5) {
            return validateStraightMove(fromIndex, toIndex) || validateDiagonalMove(fromIndex, toIndex);
        } else if (abs(piece) == 6) {
            return validateKingMoveForCheck(fromIndex, toIndex);
        }

        return false;
    }

    function validatePawnMoveForCheck(uint8 fromIndex, uint8 toIndex, bool isWhite) internal view returns (bool) {
        int8 direction = isWhite ? 1 : -1;
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

    function getPositionHash() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            board,
            whiteTurn,
            enPassantTarget,
            whiteKingMoved,
            whiteRookKingSideMoved,
            whiteRookQueenSideMoved,
            blackKingMoved,
            blackRookKingSideMoved,
            blackRookQueenSideMoved
        ));
    }

    function abs(int8 x) internal pure returns (int8) {
        return x >= 0 ? x : -x;
    }
}
