import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../utils/ownable.sol";
import "../../utils/random.sol";
import "../../engines/deck.sol";

interface IPackFactory {
    function openPack() external returns (uint256[] memory);
}

interface ITCGClass {
    function getClassName() external view returns (string memory);
    function getClassDescription() external view returns (string memory);
    function getClassImageURI() external view returns (string memory);
}

interface ITCGMacro {
    function getMacroName() external view returns (string memory);
    function getMacroDescription() external view returns (string memory);
    function getMacroImageURI() external view returns (string memory);
}

// Initial version of the Arcadium TCG pack factory
contract ArcadiumTCGPackFactory is Ownable {
    address public randomSeedGenerator;

    constructor (address _randomSeedGenerator) Ownable() {
        randomSeedGenerator = _randomSeedGenerator;
    }

    function openPack() public returns (uint256[] memory) {
        uint256 seed = IRandomSeedGenerator(randomSeedGenerator).getSeed(); // Max is 2**128 - 1
        uint256[] memory cardIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            // Extract 8 bits from the seed, for each parameter
            uint8 power = uint8(seed >> (i * 8));
            uint8 defense = uint8(seed >> (i * 8 + 1));
            uint8 speed = uint8(seed >> (i * 8 + 2));
            uint8 endurance = uint8(seed >> (i * 8 + 3));
            uint8 intelligence = uint8(seed >> (i * 8 + 4));
            uint8 luck = uint8(seed >> (i * 8 + 5));
            // Generate a card with the extracted parameters

        }
        return cardIds;
    }
}

// Card NFTs
contract ArcadiumTCG is Ownable, ERC721 {
    struct Card {
        uint256 id;                 // Unique identifier for the card
        uint8 power;                // Power score (0-255)
        uint8 defense;              // Defense score (0-255)
        uint8 speed;                // Speed score (0-255)
        uint8 endurance;            // Endurance score (0-255)
        uint8 intelligence;         // Intelligence score (0-255)
        uint8 luck;                 // Luck score (0-255)
        string name;                // Name of the card
        string description;         // Description of the card
        string imageURI;            // URI for the card's image     
        address cardClass;          // Address pointing to the card's class details
        address[] macros;           // Array of addresses for macros this card can use
    }

    address public packFactory;
    
    constructor(string memory name, string memory symbol, address packFactory) ERC721(name, symbol) Ownable() {
        packFactory = packFactory;
    }
}

// Game
contract ArcadiumTCGGame is Ownable {
    address public deckManager;

    constructor(address _packFactory, address _cardFactory, address _deckManager) Ownable() {
        packFactory = _packFactory;
        cardFactory = _cardFactory;
        deckManager = _deckManager;
    }
}