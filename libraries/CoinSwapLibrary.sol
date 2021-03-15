//SPDX-License-Identifier: TBD
pragma solidity =0.7.4;
import '../CoinSwapPair.sol';
import './SafeMath.sol';
import './SQRT.sol';
import '../CoinSwapFactory.sol';
import '../CoinSwapPair.sol';

library CoinSwapLibrary {
    using SafeMath for uint;

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'46764fb5957a3ee2ab3e61e284cdee38e2226c610cb0f29ac17855a4df31d14f'
            ))));
    }

    function getReservesAndmu(address factory, address tokenA, address tokenB) internal view returns 
                                        (uint reserveA, uint reserveB, uint mulambda) {
        (uint224 reserve, uint224 circleData) = CoinSwapPair(pairFor(factory, tokenA, tokenB)).getReserves();
        uint reserve0 = uint(reserve>>128);
        uint reserve1 = uint(uint96(reserve>>32));
        uint mulambda0 = uint(uint16(circleData >> 72))* uint56(circleData >> 160) * uint56(circleData);
        uint mulambda1 = uint(uint16(circleData >> 56))* uint56(circleData >> 104) * uint56(circleData);
        (reserveA, reserveB, mulambda) = tokenA < tokenB ?
	      (reserve0,reserve1, (mulambda0<<128) | mulambda1 ):(reserve1,reserve0, (mulambda1<<128) | mulambda0);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint mulambda) internal pure returns (uint amountOut) {
        require((amountIn > 0) && (reserveOut > 0), 'CSWP:63');
	    uint mulambda0 = (mulambda>>128);
	    uint mulambda1 = uint(uint128(mulambda));
        uint Z = 10**37-(mulambda0 * reserveIn * 1000);
        uint R0=Z*Z;
        Z= 10**37-(mulambda1 * reserveOut * 1000);
        R0 += Z*Z;
        uint ZZ = uint(10**37).sub(mulambda0 * (1000*reserveIn + amountIn * 997));  
        R0 = R0.sub(ZZ*ZZ);  
        R0 = SQRT.sqrt(R0);
        amountOut = R0.sub(Z) / (mulambda1 * 1000);
	    if (amountOut > reserveOut) amountOut = reserveOut;
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint mulambda) internal pure returns (uint amountIn) {
        uint mulambda0 = (mulambda>>128);
	    uint mulambda1 = uint(uint128(mulambda));
        uint Z= 10**37-(mulambda1 * reserveOut * 1000);
        uint R1 = Z*Z;
	    Z = 10**37-(mulambda0 * reserveIn * 1000);
        R1 += Z*Z;
        uint ZZ = 10**37-(mulambda1 * 1000* (reserveOut.sub(amountOut)));  
	    R1 =R1.sub(ZZ*ZZ); 
        amountIn = 1+ (Z.sub(SQRT.sqrt(R1))) / (mulambda0 * 997) ; 
    }

    function getAmountsOut(address factory, uint amountIn, address[] memory path) 
            internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'CSWP:65');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut, uint mulambda) 
                = getReservesAndmu(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, mulambda);
        }
    }

    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'CSWP:66');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut, uint mulambda) 
                = getReservesAndmu(factory, path[i-1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, mulambda);
        }
    }
}

