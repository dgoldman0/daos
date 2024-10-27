// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import "../../utils/irandomseedgenerator.sol";

contract SudokuGameData {
    uint256 public gameCounter;

    struct SudokuGame {
        uint256 gameId;
        uint8[9][9] board;
        bool isActive;
    }

    mapping(uint256 => SudokuGame) public games;

    event GameCreated(uint256 indexed gameId, uint8[9][9] board);

    function storeGame(uint8[9][9] memory board) external returns (uint256) {
        games[gameCounter] = SudokuGame(gameCounter, board, true);
        emit GameCreated(gameCounter, board);
        gameCounter++;
        return gameCounter - 1;
    }

    function getGame(uint256 gameId) external view returns (SudokuGame memory) {
        return games[gameId];
    }
}

contract SudokuGameManager {
    IRandomSeedGenerator public randomSeedGenerator;
    SudokuGameData public gameData;

    event GameValidated(uint256 indexed gameId, bool isValid);

    constructor(address _randomSeedGenerator, address _gameDataAddress) {
        randomSeedGenerator = IRandomSeedGenerator(_randomSeedGenerator);
        gameData = SudokuGameData(_gameDataAddress);
    }

    function initializeGame() external {
        uint256 seed = randomSeedGenerator.getSeed();
        uint8[9][9] memory board = generateSudokuBoard(seed);
        gameData.storeGame(board);
    }

    function generateSudokuBoard(uint256 seed) internal view returns (uint8[9][9] memory) {
        uint8[9][9] memory board;
        uint256 randomNumber = seed;
        
        // Fill the board with numbers using the seed
        for (uint8 i = 0; i < 9; i++) {
            for (uint8 j = 0; j < 9; j++) {
                randomNumber = uint256(keccak256(abi.encodePacked(randomNumber, block.timestamp, block.prevrandao, i, j)));
                board[i][j] = uint8((randomNumber % 9) + 1);
            }
        }

        // Remove some numbers to create a playable Sudoku puzzle
        for (uint8 i = 0; i < 9; i++) {
            for (uint8 j = 0; j < 9; j++) {
                randomNumber = uint256(keccak256(abi.encodePacked(randomNumber, block.timestamp, i, j)));
                if (randomNumber % 2 == 0) {
                    board[i][j] = 0; // Remove some cells to create blanks
                }
            }
        }

        return board;
    }

    function isValidSudoku(uint8[9][9] memory board) public pure returns (bool) {
        for (uint8 i = 0; i < 9; i++) {
            uint16 rowBits = 0;
            uint16 colBits = 0;
            uint16 gridBits = 0;

            for (uint8 j = 0; j < 9; j++) {
                uint8 rowVal = board[i][j];
                uint8 colVal = board[j][i];
                uint8 gridVal = board[(i / 3) * 3 + j / 3][(i % 3) * 3 + j % 3];

                // Fail immediately if the value is 0 (blank) or greater than 9
                if (rowVal == 0 || rowVal > 9 || colVal == 0 || colVal > 9 || gridVal == 0 || gridVal > 9) {
                    return false;
                }

                uint16 rowMask = uint16(1 << (rowVal - 1));
                uint16 colMask = uint16(1 << (colVal - 1));
                uint16 gridMask = uint16(1 << (gridVal - 1));

                // Check for duplicates
                if ((rowBits & rowMask) != 0 || (colBits & colMask) != 0 || (gridBits & gridMask) != 0) {
                    return false;
                }

                // Set bits for row, column, and grid
                rowBits |= rowMask;
                colBits |= colMask;
                gridBits |= gridMask;
            }
        }

        return true;
    }
}
