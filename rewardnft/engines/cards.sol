// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/ownable.sol";

interface IRandomSeedGenerator {
    function getSeed() external returns (uint256 seed);
}

contract DeckManager is Ownable {
    IRandomSeedGenerator public randomSeed;
    address public deckAuthorizer;

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

    constructor(address _randomSeed) Ownable() {
        randomSeed = IRandomSeedGenerator(_randomSeed);
        deckAuthorizer = msg.sender;

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

    // Get the cards in the deck
    function getDeck(uint256 deckId) external view returns (uint256[] memory) {
        return decks[deckId].cardIds;
    }
    // Get remaining cards in the deck
    function getRemainingCards(uint256 deckId) external view returns (uint256[] memory) {
        return decks[deckId].remainingCards;
    }
    // Get already chosen cards
    function getChosenCards(uint256 deckId) external view returns (uint256[] memory) {
        return decks[deckId].chosenCards;
    }

    // Choose a card at random. Consider that the random number may be anywhere between 0 and 2^128-1
    function chooseCard(uint256 deckId) external returns (uint256) {
        Deck storage deck = decks[deckId];
        require(deck.remainingCards.length > 0, "No cards remaining");
        uint256 random = randomSeed.getSeed();
        uint256 index = random % deck.remainingCards.length;
        uint256 chosenCard = deck.remainingCards[index];
        deck.chosenCards.push(chosenCard);
        deck.remainingCards[index] = deck.remainingCards[deck.remainingCards.length - 1];
        deck.remainingCards.pop();
        return chosenCard;
    }

    // Reset the deck to its original state (copy cardIds to remainingCards and clear chosenCards)
    function resetDeck(uint256 deckId) external onlyOwner {
        Deck storage deck = decks[deckId];
        for (uint256 i = 0; i < deck.cardIds.length; i++) {
            deck.remainingCards[i] = deck.cardIds[i];
        }
        deck.chosenCards = new uint256[](0);
    }

    // Set the random seed generator
    function setRandomSeedGenerator(address _randomSeedGenerator) external onlyOwner {
        randomSeed = IRandomSeedGenerator(_randomSeed);
    }

    function setDeckAuthorizer(address _deckAuthorizer) external onlyOwner {
        deckAuthorizer = _deckAuthorizer;
    }
}