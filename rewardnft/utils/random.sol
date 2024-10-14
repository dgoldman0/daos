// SPDX-License-Identifier: MIT
import './ownable.sol';

// Interface for Uniswap V3 Pool
interface IUniswapV3Pool {
    function observe(uint32[] calldata secondsAgos) 
        external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128);
}

// Interface for Uniswap V3 Factory
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract RandomSeed is Ownable {
    IUniswapV3Factory public factory;
    struct Pool {
        address tokenA;
        address tokenB;
        uint24 fee;
    }
    Pool[] public pools;

    constructor() {
        // Valid for Arbitrum
        factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        // Add the LINK-UNI pool with 3000 fee tier (Arbitrum)
        pools.push(Pool(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 3000)); // Works
        // Add ARB-UNI pool with 3000 fee tier (Arbitrum)
        pools.push(Pool(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 3000)); // Works
        // Add ARB-LINK pool with 3000 fee tier (Arbitrum)
        pools.push(Pool(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4, 3000));
        // Add USDC-USDT pool with 3000 fee tier (Arbitrum)
        pools.push(Pool(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, 3000));
        // Might need to add in lower fee ones. 0.01% fee tier
        pools.push(Pool(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 100));
        pools.push(Pool(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 100));
        pools.push(Pool(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, 100));
    }

    // Get the sum of tickCumulatives for the most recent price
    function getSeed() public view returns (int256 tickSum) {
        int256 sum = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            sum += int256(getMostRecentTick(i));
        }
        return sum;
    }

    function getMostRecentTick(uint256 poolIndex) public view returns (int56 tickCumulative) {
        require(poolIndex < pools.length, "Invalid pool index");
        address poolAddress = getPool(pools[poolIndex].tokenA, pools[poolIndex].tokenB, pools[poolIndex].fee);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;  // Asking for the most recent price (0 seconds ago)
        
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        
        return tickCumulatives[0];  // The most recent tick cumulative
    }

    function getPool(address tokenA, address tokenB, uint24 fee) public view returns (address poolAddress) {
        require(address(factory) != address(0), "Invalid factory address");
        return IUniswapV3Factory(factory).getPool(tokenA, tokenB, fee);
    }

    function addPool(address tokenA, address tokenB, uint24 fee) public onlyOwner {
        pools.push(Pool(tokenA, tokenB, fee));
    }

    function removePool(uint256 poolIndex) public onlyOwner {
        require(poolIndex < pools.length, "Invalid pool index");
        pools[poolIndex] = pools[pools.length - 1];
        pools.pop();
    }
}