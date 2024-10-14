// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/ownable.sol";

interface IRandomSeedGenerator {
    function getSeed() external returns (uint256 seed);
}

contract DeckManager is Ownable {
    IRandomSeedGenerator public randomSeed;

    // Generic deck which can be linked to any tokens 1:1 through cardIds
    struct Deck {
        uint256 id;
        string name;
        uint256[] cardIds;
        uint256[] remainingCards;
        uint256[] chosenCards;
    }

    // Mapping of deckId to deck
    mapping(uint256 => Deck) public decks;
    uint256 nextDeckId = 1;

    constructor(address _randomSeed) {
        randomSeed = IRandomSeedGenerator(_randomSeed);
    }

    function addDeck(string memory name, uint256[] memory cardIds) external onlyOwner {
        uint256[] memory remainingCards = new uint256[](cardIds.length);
        for (uint256 i = 0; i < cardIds.length; i++) {
            remainingCards[i] = cardIds[i];
        }
        decks[nextDeckId] = Deck({
            id: nextDeckId,
            name: name,
            cardIds: cardIds,
            remainingCards: remainingCards,
            chosenCards: new uint256[](0)});
        nextDeckId++;
    }

    function setRandomSeed(address _randomSeed) external onlyOwner {
        randomSeed = IRandomSeedGenerator(_randomSeed);
    }
}