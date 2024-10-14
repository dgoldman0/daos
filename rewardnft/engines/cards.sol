// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/ownable.sol";

interface IRandomSeedGenerator {
    function getSeed() external returns (uint256 seed);
}

interface IDeckManager {
    function addDeck(string memory name, uint256[] memory cardIds, bool allow_duplicates) external;
    function addCardToDeck(uint256 deckId, uint256 cardId) external;
    function removeCardFromDeck(uint256 deckId, uint256 cardId, bool allinstancs) external;
    function chooseCard(uint256 deckId) external returns (uint256);
    function returnCard(uint256 deckId, uint256 cardId) external;
    function resetDeck(uint256 deckId) external;
}

contract DeckManager is Ownable {
    IRandomSeedGenerator public randomSeedGenerator;
    address public deckAuthorizer;

    // Generic deck which can be linked to any tokens 1:1 through cardIds
    struct Deck {
        uint256 id;
        string name;
        uint256[] cardIds;
        uint256[] remainingCards;
        uint256[] chosenCards;
        bool duplicatesAllowed;
    }

    // Mapping of deckId to deck
    mapping(uint256 => Deck) public decks;
    // Mapping of deckId to cardId to check if the card is in the deck
    mapping (uint256 => mapping (uint256 => bool)) public isInDeck;
    uint256 nextDeckId = 1;

    modifier onlyDeckAuthorizer() {
        require(msg.sender == deckAuthorizer, "Not the deck authorizer");
        _;
    }

    constructor(address _randomSeedGenerator) Ownable() {
        randomSeedGenerator = IRandomSeedGenerator(_randomSeedGenerator);
        deckAuthorizer = msg.sender;

    }

    function addDeck(string memory name, uint256[] memory cardIds, bool allow_duplicates) external onlyDeckAuthorizer {
        uint256[] memory remainingCards = new uint256[](cardIds.length);
        for (uint256 i = 0; i < cardIds.length; i++) {
            remainingCards[i] = cardIds[i];
        }
        decks[nextDeckId] = Deck({
            id: nextDeckId,
            name: name,
            cardIds: cardIds,
            remainingCards: remainingCards,
            chosenCards: new uint256[](0),
            duplicatesAllowed: allow_duplicates});
        nextDeckId++;
    }

    // Add a card to the deck
    function addCardToDeck(uint256 deckId, uint256 cardId) external onlyDeckAuthorizer {
        require(decks[deckId].duplicatesAllowed == true || isInDeck[deckId][cardId] == false, "Duplicates not allowed");
        require(decks[deckId].chosenCards.length == 0, "Deck in use");
        Deck storage deck = decks[deckId];
        deck.cardIds.push(cardId);
        deck.remainingCards.push(cardId);
        isInDeck[deckId][cardId] = true;
    }

    // Remove a card from the deck
    function removeCardFromDeck(uint256 deckId, uint256 cardId, bool allinstancs) external onlyDeckAuthorizer {
        require(isInDeck[deckId][cardId] == true, "Card not in deck");
        require(decks[deckId].chosenCards.length == 0, "Deck in use");
        Deck storage deck = decks[deckId];
        for (uint256 i = 0; i < deck.cardIds.length; i++) {
            if (deck.cardIds[i] == cardId) {
                deck.cardIds[i] = deck.cardIds[deck.cardIds.length - 1];
                deck.cardIds.pop();
                if (!allinstancs)
                    break;
            }
        }
        for (uint256 i = 0; i < deck.remainingCards.length; i++) {
            if (deck.remainingCards[i] == cardId) {
                deck.remainingCards[i] = deck.remainingCards[deck.remainingCards.length - 1];
                deck.remainingCards.pop();
                if (!allinstancs)
                    break;
            }
        }
        // Check if there's at least one more instance of the card in the deck, which we can skip if allinstances is true or if duplicates are not allowed
        bool found = false;
        if (allinstancs || !deck.duplicatesAllowed) {
            for (uint256 i = 0; i < deck.cardIds.length; i++) {
                if (deck.cardIds[i] == cardId) {
                    found = true;
                    break;
                }
            }
        }
        isInDeck[deckId][cardId] = found;
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
    function chooseCard(uint256 deckId) external onlyDeckAuthorizer returns (uint256) { 
        Deck storage deck = decks[deckId];
        require(deck.remainingCards.length > 0, "No cards remaining");
        uint256 random = randomSeedGenerator.getSeed();
        uint256 index = random % deck.remainingCards.length;
        uint256 chosenCard = deck.remainingCards[index];
        deck.chosenCards.push(chosenCard);
        deck.remainingCards[index] = deck.remainingCards[deck.remainingCards.length - 1];
        deck.remainingCards.pop();
        return chosenCard;
    }

    // Reset the deck to its original state (copy cardIds to remainingCards and clear chosenCards)
    function resetDeck(uint256 deckId) external onlyDeckAuthorizer {
        Deck storage deck = decks[deckId];
        delete deck.remainingCards;
        for (uint256 i = 0; i < deck.cardIds.length; i++) {
            deck.remainingCards.push(deck.cardIds[i]);
        }
        delete deck.chosenCards;
    }

    // Set the random seed generator
    function setRandomSeedGenerator(address _randomSeedGenerator) external onlyOwner {
        randomSeedGenerator = IRandomSeedGenerator(_randomSeedGenerator);
    }

    function setDeckAuthorizer(address _deckAuthorizer) external onlyOwner {
        deckAuthorizer = _deckAuthorizer;
    }
}