interface IDeckManager {
    function addDeck(string memory name, uint256[] memory cardIds, bool allow_duplicates) external;
    function addCardToDeck(uint256 deckId, uint256 cardId) external;
    function removeCardFromDeck(uint256 deckId, uint256 cardId, bool allinstancs) external;
    function chooseCard(uint256 deckId) external returns (uint256);
    function returnCard(uint256 deckId, uint256 cardId) external;
    function resetDeck(uint256 deckId) external;
}
