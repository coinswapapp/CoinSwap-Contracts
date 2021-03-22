//SPDX-License-Identifier: TBD
pragma solidity =0.7.4;

import './CoinSwapFactory.sol';



interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract CoinSwapRouterV1 { 
    using SafeMath for uint;
    address public immutable factory;
    address public immutable WETH;
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'CSWP:30');
        _;
    }
    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }
        
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin, 
        uint amountBMin,
        uint224 circle //lambda0/lambda1 in circle needs in order of token0<token1 
    ) internal virtual returns (uint amountA, uint amountB, address pairForAB) {
        pairForAB =CoinSwapFactory(factory).getPair(tokenA, tokenB);
        if (pairForAB == address(0)) {
            pairForAB= CoinSwapFactory(factory).createPair(tokenA,tokenB,circle);
        }
        (uint reserveA, uint reserveB,) = CoinSwapLibrary.getReservesAndmu(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
          (amountA, amountB) = (amountADesired, amountBDesired);
        } else if (reserveA == 0) {
	        (amountA, amountB) = (0, amountBDesired);
	    } else if (reserveB == 0) {
	        (amountA, amountB) = (amountADesired,0);
	    } else {
	        uint amountBOptimal = (amountADesired *reserveB) / reserveA;
	        if (amountBOptimal <= amountBDesired) {
	            require(amountBOptimal >= amountBMin, 'CSWP:31');
	            (amountA, amountB) = (amountADesired, amountBOptimal);
	        } else {
	            uint amountAOptimal = (amountBDesired *reserveA) / reserveB;
	            assert(amountAOptimal <= amountADesired);
	            require(amountAOptimal >= amountAMin, 'CSWP:32');
	            (amountA, amountB) = (amountAOptimal, amountBDesired);
	        }
	    }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amtADesired,
        uint amtBDesired,
        uint amtAMin,
        uint amtBMin,
        address to,
        uint deadline,
        uint224 circle
    ) external virtual ensure(deadline) returns (uint amtA, uint amtB, uint liquidity) {
        address pair;
        (amtA, amtB, pair) = _addLiquidity(tokenA, tokenB, amtADesired, amtBDesired, amtAMin, amtBMin, circle);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amtA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amtB);
        liquidity = CoinSwapPair(pair).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint amtTokenDesired,
        uint amtTokenMin,
        uint amtETHMin,
        address to,
        uint deadline,
        uint224 circle
    ) external virtual payable ensure(deadline) returns (uint amtToken, uint amtETH, uint liquidity) {
        address pair;
        (amtToken, amtETH, pair) = _addLiquidity(token,WETH,amtTokenDesired,msg.value,amtTokenMin,amtETHMin,circle);
                TransferHelper.safeTransferFrom(token, msg.sender, pair, amtToken);
        IWETH(WETH).deposit{value: amtETH}();
        assert(IWETH(WETH).transfer(pair, amtETH));
        liquidity = CoinSwapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amtETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amtETH);
    }

    // **** REMOVE LIQUIDITY **** 
    // For OCI market, we do not have specific remove liquidity function
    // but one can remove a pair by providing OCI-ed addresses
       function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amtAMin,
        uint amtBMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = CoinSwapLibrary.pairFor(factory, tokenA, tokenB);
        CoinSwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        uint192 amount = CoinSwapPair(pair).burn(to);
        (amountA, amountB) = tokenA < tokenB ? (uint(amount>>96), uint(uint96(amount))) : (uint(uint96(amount)), uint(amount>>96));
        require((amountA >= amtAMin) && (amountB >= amtBMin), 'CSWP:33');
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountA, uint amountB) {
        address pair = CoinSwapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        CoinSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountToken, uint amountETH) {
        address pair = CoinSwapLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        CoinSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }
    
    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountETH) {
        address pair = CoinSwapLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        CoinSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }
    

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input < output ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? CoinSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            CoinSwapPair(CoinSwapLibrary.pairFor(factory, input, output)).swap(
                uint192((amount0Out<<96) | amount1Out), to, new bytes(0));
        }
    }
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint[] memory amounts) {
        amounts = CoinSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CSWP:34');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint[] memory amounts) {
        amounts = CoinSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'CSWP:35');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'CSWP:36');
        amounts = CoinSwapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CSWP:37');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(CoinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'CSWP:38');
        amounts = CoinSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'CSWP:39');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'CSWP:40');
        amounts = CoinSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CSWP:41');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'CSWP:42');
        amounts = CoinSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'CSWP:43');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(CoinSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            CoinSwapPair pair = CoinSwapPair(CoinSwapLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
	    
	    (uint reserveInput, uint reserveOutput, uint mulambda) = CoinSwapLibrary.getReservesAndmu(factory, input, output);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = CoinSwapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput, mulambda);
            }
            (uint amount0Out, uint amount1Out) = input < output ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? CoinSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(uint192(amount0Out<<96 | amount1Out), to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'CSWP:44'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'CSWP:45');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(CoinSwapLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'CSWP:46'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'CSWP:47');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CoinSwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'CSWP:48');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }
    
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint mulambda) public pure returns (uint amountOut) {
        return CoinSwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut, mulambda);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint mulambda) public pure returns (uint amountIn) {
        return CoinSwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut, mulambda);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        return CoinSwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view returns (uint[] memory amounts) {
        return CoinSwapLibrary.getAmountsIn(factory, amountOut, path);
    }
}



// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'CSWP70');
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'CSWP71');
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'CSWP72');
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'CSWP73');
    }
}

library CoinSwapLibrary {
    using SafeMath for uint;

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'08d6ace72c919d3777e7a6a0ae82941b79932ea4e7b37e16d8c04f7fd2783574'
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
