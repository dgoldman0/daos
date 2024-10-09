// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library ChessGame {

    // Enum to represent piece types
    enum PieceType {
        None,     // 0: Empty square
        Pawn,     // 1
        Rook,     // 2
        Knight,   // 3
        Bishop,   // 4
        Queen,    // 5
        King      // 6
    }

    // Enum to represent player color
    enum PlayerColor {
        White,    // 0
        Black     // 1
    }

    // Struct to represent a piece (type and color)
    struct Piece {
        PieceType pieceType;
        PlayerColor color;
    }

    // Struct to represent a move
    struct Move {
        uint8 from;  // From square (0-63)
        uint8 to;    // To square (0-63)
        bytes32 moveData; // Extra information (promotion, en passant, etc.)
    }

    // Game state
    struct GameState {
        address white;    // Address of the white player
        address black;    // Address of the black player
        Piece[64] board;  // 64-element array representing the board
        Move[] moveHistory; // Array to store all moves made
        bool isWhiteTurn;  // Track whose turn it is
    }

    // Initialize a new game
    function initialize(GameState storage self, address _white, address _black) public {
        self.white = _white;
        self.black = _black;
        self.isWhiteTurn = true;

        // Clear the board
        for (uint8 i = 0; i < 64; i++) {
            self.board[i] = Piece(PieceType.None, PlayerColor.White); // Empty board initially
        }

        // Set up the starting positions for pawns (rows 2 and 7)
        for (uint8 i = 8; i < 16; i++) {
            self.board[i] = Piece(PieceType.Pawn, PlayerColor.White);  // White pawns on row 2
            self.board[i + 40] = Piece(PieceType.Pawn, PlayerColor.Black); // Black pawns on row 7
        }

        // Set up the starting positions for rooks, knights, bishops, queen, and king (rows 1 and 8)
        // White pieces on row 1
        self.board[0] = Piece(PieceType.Rook, PlayerColor.White);
        self.board[1] = Piece(PieceType.Knight, PlayerColor.White);
        self.board[2] = Piece(PieceType.Bishop, PlayerColor.White);
        self.board[3] = Piece(PieceType.Queen, PlayerColor.White);
        self.board[4] = Piece(PieceType.King, PlayerColor.White);
        self.board[5] = Piece(PieceType.Bishop, PlayerColor.White);
        self.board[6] = Piece(PieceType.Knight, PlayerColor.White);
        self.board[7] = Piece(PieceType.Rook, PlayerColor.White);

        // Black pieces on row 8
        self.board[56] = Piece(PieceType.Rook, PlayerColor.Black);
        self.board[57] = Piece(PieceType.Knight, PlayerColor.Black);
        self.board[58] = Piece(PieceType.Bishop, PlayerColor.Black);
        self.board[59] = Piece(PieceType.Queen, PlayerColor.Black);
        self.board[60] = Piece(PieceType.King, PlayerColor.Black);
        self.board[61] = Piece(PieceType.Bishop, PlayerColor.Black);
        self.board[62] = Piece(PieceType.Knight, PlayerColor.Black);
        self.board[63] = Piece(PieceType.Rook, PlayerColor.Black);
    }

    // Apply a move from one square to another
    function applyMove(GameState storage self, uint8 from, uint8 to) public {
        require(from < 64 && to < 64, "Invalid move: out of board bounds");

        // Get the piece at the 'from' position
        Piece memory piece = self.board[from];
        require(piece.pieceType != PieceType.None, "No piece at from square");

        // Check if it's the current player's turn
        if (self.isWhiteTurn) {
            require(msg.sender == self.white, "Not white player's turn");
            require(piece.color == PlayerColor.White, "Not white piece");
        } else {
            require(msg.sender == self.black, "Not black player's turn");
            require(piece.color == PlayerColor.Black, "Not black piece");
        }

        // Validate the move
        require(isMoveValid(self, from, to), "Invalid move according to piece rules");

        // Move the piece to the 'to' position
        self.board[to] = piece;
        self.board[from] = Piece(PieceType.None, PlayerColor.White); // Clear the from square

        // Add the move to the move history
        self.moveHistory.push(Move(from, to, bytes32(0))); // Optionally use moveData for special cases like promotion

        // Change turn
        self.isWhiteTurn = !self.isWhiteTurn;
    }

    // Helper function to validate moves
    function isMoveValid(GameState storage self, uint8 from, uint8 to) internal view returns (bool) {
        Piece memory piece = self.board[from];
        Piece memory targetPiece = self.board[to];

        uint8 fromRow = from / 8;
        uint8 fromCol = from % 8;
        uint8 toRow = to / 8;
        uint8 toCol = to % 8;

        // Check if target square has a piece of the same color
        if (targetPiece.pieceType != PieceType.None && targetPiece.color == piece.color) {
            return false;
        }

        // Calculate differences
        int8 rowDiff = int8(int8(toRow) - int8(fromRow));
        int8 colDiff = int8(int8(toCol) - int8(fromCol));

        // Validate movement based on the piece type
        if (piece.pieceType == PieceType.Pawn) {
            return validatePawnMove(self, piece, from, to, fromRow, fromCol, toRow, toCol, rowDiff, colDiff);
        } else if (piece.pieceType == PieceType.Rook) {
            return validateRookMove(self, from, to, fromRow, fromCol, toRow, toCol);
        } else if (piece.pieceType == PieceType.Knight) {
            return validateKnightMove(rowDiff, colDiff);
        } else if (piece.pieceType == PieceType.Bishop) {
            return validateBishopMove(self, from, to, rowDiff, colDiff);
        } else if (piece.pieceType == PieceType.Queen) {
            return validateQueenMove(self, from, to, fromRow, fromCol, toRow, toCol, rowDiff, colDiff);
        } else if (piece.pieceType == PieceType.King) {
            return validateKingMove(rowDiff, colDiff);
        }

        return false;
    }

    // Validate pawn moves
    function validatePawnMove(
        GameState storage self,
        Piece memory piece,
        uint8 from,
        uint8 to,
        uint8 fromRow,
        uint8 fromCol,
        uint8 toRow,
        uint8 toCol,
        int8 rowDiff,
        int8 colDiff
    ) internal view returns (bool) {
        Piece memory targetPiece = self.board[to];

        if (piece.color == PlayerColor.White) {
            // Move forward
            if (colDiff == 0 && targetPiece.pieceType == PieceType.None) {
                if (rowDiff == 1) {
                    return true; // Move one square forward
                } else if (rowDiff == 2 && fromRow == 1 && self.board[from + 8].pieceType == PieceType.None) {
                    return true; // Move two squares from starting position
                }
            }
            // Capture
            else if (rowDiff == 1 && (colDiff == 1 || colDiff == -1) && targetPiece.pieceType != PieceType.None && targetPiece.color == PlayerColor.Black) {
                return true; // Diagonal capture
            }
        } else {
            // Move forward
            if (colDiff == 0 && targetPiece.pieceType == PieceType.None) {
                if (rowDiff == -1) {
                    return true; // Move one square forward
                } else if (rowDiff == -2 && fromRow == 6 && self.board[from - 8].pieceType == PieceType.None) {
                    return true; // Move two squares from starting position
                }
            }
            // Capture
            else if (rowDiff == -1 && (colDiff == 1 || colDiff == -1) && targetPiece.pieceType != PieceType.None && targetPiece.color == PlayerColor.White) {
                return true; // Diagonal capture
            }
        }
        return false;
    }

    // Validate rook moves
    function validateRookMove(
        GameState storage self,
        uint8 from,
        uint8 to,
        uint8 fromRow,
        uint8 fromCol,
        uint8 toRow,
        uint8 toCol
    ) internal view returns (bool) {
        if (fromRow == toRow || fromCol == toCol) {
            return isPathClear(self, from, to);
        }
        return false;
    }

    // Validate knight moves
    function validateKnightMove(int8 rowDiff, int8 colDiff) internal pure returns (bool) {
        if ((abs(rowDiff) == 2 && abs(colDiff) == 1) || (abs(rowDiff) == 1 && abs(colDiff) == 2)) {
            return true;
        }
        return false;
    }

    // Validate bishop moves
    function validateBishopMove(
        GameState storage self,
        uint8 from,
        uint8 to,
        int8 rowDiff,
        int8 colDiff
    ) internal view returns (bool) {
        if (abs(rowDiff) == abs(colDiff)) {
            return isPathClear(self, from, to);
        }
        return false;
    }

    // Validate queen moves
    function validateQueenMove(
        GameState storage self,
        uint8 from,
        uint8 to,
        uint8 fromRow,
        uint8 fromCol,
        uint8 toRow,
        uint8 toCol,
        int8 rowDiff,
        int8 colDiff
    ) internal view returns (bool) {
        if (fromRow == toRow || fromCol == toCol || abs(rowDiff) == abs(colDiff)) {
            return isPathClear(self, from, to);
        }
        return false;
    }

    // Validate king moves
    function validateKingMove(int8 rowDiff, int8 colDiff) internal pure returns (bool) {
        if (abs(rowDiff) <= 1 && abs(colDiff) <= 1) {
            return true;
        }
        return false;
    }

    // Helper function to check if the path between two squares is clear (for rooks, bishops, and queens)
    function isPathClear(GameState storage self, uint8 from, uint8 to) internal view returns (bool) {
        int8 fromRow = int8(from / 8);
        int8 fromCol = int8(from % 8);
        int8 toRow = int8(to / 8);
        int8 toCol = int8(to % 8);

        int8 rowDirection = (toRow > fromRow) ? int8(1) : (toRow < fromRow) ? int8(-1) : int8(0);
        int8 colDirection = (toCol > fromCol) ? int8(1) : (toCol < fromCol) ? int8(-1) : int8(0);

        int8 currentRow = fromRow + rowDirection;
        int8 currentCol = fromCol + colDirection;

        while (currentRow != toRow || currentCol != toCol) {
            if (currentRow < 0 || currentRow >= 8 || currentCol < 0 || currentCol >= 8) {
                return false; // Out of bounds
            }

            uint8 currentSquare = uint8(uint8(currentRow) * 8 + uint8(currentCol));
            if (self.board[currentSquare].pieceType != PieceType.None) {
                return false; // Path is blocked
            }

            currentRow += rowDirection;
            currentCol += colDirection;
        }

        return true;
    }

    // Helper function to compute absolute value of int8
    function abs(int8 x) internal pure returns (uint8) {
        return uint8(x >= 0 ? x : -x);
    }
}
