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

contract UniswapCumulativeTick {
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
        // Add the UNI-LINK pool with 3000 fee tier (Arbitrum)
        pools.push(Pool(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4, 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0, 3000));

    }

    function getMostRecentPrice(uint256 poolIndex) public view returns (int56 tickCumulative) {
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
}