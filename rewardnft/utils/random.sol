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
        // ETH-ARB pool with 0.05% fee tier (Arbitrum)
        pools.push(Pool(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 0x912CE59144191C1204E64559FE8253a0e49E6548, 500));
        // Add WBTC-ETH pool with 0.05 fee tier (Arbitrum)
        pools.push(Pool(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 500));
        // Add ETH-USDC pool with 0.05 fee tier (Arbitrum)
        pools.push(Pool(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, 500));
        // Add ARB-USDC pool with 0.05 fee tier (Arbitrum)
        pools.push(Pool(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, 500));
        // Add the LINK-UNI pool with 3% fee tier (Arbitrum)
        pools.push(Pool(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 3000));
        // Add ARB-UNI pool with 3% fee tier (Arbitrum)
        pools.push(Pool(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 3000));
        // Add ARB-LINK pool with 3% fee tier (Arbitrum)
        pools.push(Pool(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4, 3000));
        // Add USDC-USDT pool with 3% fee tier (Arbitrum)
        pools.push(Pool(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, 3000));
        pools.push(Pool(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 100));
        pools.push(Pool(0x912CE59144191C1204E64559FE8253a0e49E6548, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 100));
        pools.push(Pool(0xaf88d065e77c8cC2239327C5EDb3A432268e5831, 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, 100));
        for (uint256 i = 0; i < pools.length; i++) {
            // Ensure that the pool is actually a pool
            Pool memory pool = pools[i];
            address poolAddress = getPool(pool.tokenA, pool.tokenB, pool.fee);   
            require(poolAddress != address(0), "Invalid pool");         
        }
    }

    function getSeed() public view returns (uint256 tickSum) {
        uint256 sum = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            int256 tick = int256(getMostRecentTick(i));
            uint256 tickAbs = uint256(tick < 0 ? -tick : tick);
            sum += tickAbs ** 3; // (int56)^3 => (uint55)^3 => uint165 
        }
        return sum % 2**128;  // Transform into a 128-bit number
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