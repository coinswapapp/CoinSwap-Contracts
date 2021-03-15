//SPDX-License-Identifier: TBD
pragma solidity =0.7.4;

import './CoinSwapERC20.sol';
import './interfaces/IERC20.sol';
import './CoinSwapFactory.sol';
import './interfaces/ICoinSwapCallee.sol';
import './libraries/SQRT.sol';
import './libraries/SafeMath.sol';

contract CoinSwapPair is CoinSwapERC20 {
    using SafeMath for uint;
    address public patron;
    address public factory;
    address public token0; // token0 < token1
    address public token1;
    uint224 private reserve; //reserve0(96) | reserve1(96) | blockTimestampLast(32) 
                             // reserve is scalled: all tokens converted to 18 decimals 
    uint private unlocked = 1;
    uint public priceCumulative; //=Delta_y/Delta_x: 96-fractional bits; allows overflow
    uint224 private circleData;
    /** 
      circleData = ICO(8) | 10**(18-d0) (56) | 10**(18-d1) (56)| r (16)| lambda0(16)| lambda1(16)| mu(56)
      d0 and d1 are the decimals of the tokens respectively. It is requried that d0>=2 and d1>=2
         (x-10^9)^2+(y-10^9)^2=(10000+r)*10^14; lambda0 * x0 \sim lambda1 * y0
        ICO=0: regular pair. ICO>0：ICO offers
    */
    
    modifier lock() {
        require(unlocked == 1, 'CSWP:1');
    	unlocked = 0;
        _;
        unlocked = 1;
    }
    
    event Swap(address indexed,uint192,uint192,address indexed); 
    event Sync(uint);
    event Mint(address indexed sender, uint192);
    event Burn(address indexed sender, uint192, address indexed to);
    
    constructor() {factory = msg.sender; patron=tx.origin;}
    function initialize(address _token0, address _token1, uint224 circle) external {
        //circle needs to in order of token0<token1
        require(circleData == 0, 'CSWP:2');
        token0 = _token0;
        token1 = _token1;
        circleData = circle;  // validity of circle should be checked by CoinSwapFactory
    }

    function ICO(uint224 _circleData)  external {
        require( (tx.origin==patron) && (circleData >> 216) >0, 'CSWP:3');//to close ICO, set (circleData >> 216) = 0x00
        circleData = _circleData;
    }

    function setPatron(address _patron)  external {
        require( (tx.origin==patron), 'CSWP:11');
        patron = _patron;
    }
    
    function getReserves() public view returns (uint224 _reserve, uint224 _circleData) {
        _circleData = circleData;
        uint224 R = reserve; 
        _reserve = (( (R >> 128)/uint56(_circleData>>160) )<<128) + (uint224((uint96(R >> 32)) / uint56(_circleData >> 104))<<32) + uint32(R) ;
    }
    
    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'CSWP:6');
    }

    function revisemu(uint192 balance) private returns (uint56 _mu) {
        // input balance should be scaled
        require(balance>0, 'CSWP:4');
    	uint224 _circleData = circleData;
        uint X = uint(balance>>96) *      uint16(_circleData >> 72)* uint56(_circleData >> 160);
        uint Y = uint(uint96(balance)) *  uint16(_circleData >> 56)* uint56(_circleData >> 104);
        uint XpY =  X + Y;
        uint X2pY2 = (X*X) + (Y*Y);
       	X = XpY*100;
       	Y = (X*X)  + X2pY2 * (10000+ uint16(_circleData>>88));
        uint Z= X2pY2 * 20000;
    	require(Y>Z, 'CSWP:5');
        Y = SQRT.sqrt(Y-Z); 
        Z = Y > X ? X + Y : X-Y;
        _mu =  uint56(1)+uint56(((10**32)*Z) / X2pY2);
        circleData = (_circleData & 0xFF_FFFFFFFFFFFFFF_FFFFFFFFFFFFFF_FFFF_FFFF_FFFF_00000000000000) | uint224(_mu);
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance) private {
        // input balance should be scaled
	    uint32 lastTime = uint32(balance);	
        uint32 deltaTime = uint32(block.timestamp) -lastTime ;
        if (deltaTime>0 && lastTime>0) {
    	    uint circle = circleData;
            uint lambda0 = uint16(circle >> 72);
            uint lambda1 = uint16(circle >> 56);
	        uint CmulambdaX = 10**34 - (balance>>128)     *lambda0*uint56(circle)*uint56(circle >> 160);
            uint CmulambdaY = 10**34 - uint96(balance>>32)*lambda1*uint56(circle)*uint56(circle >> 104); 
	        priceCumulative += (((lambda0*CmulambdaX)<< 96)/(lambda1*CmulambdaY)) * deltaTime;  
        }
        reserve = uint224(balance +deltaTime);
        emit Sync(balance>>32);
    }

    function _mintFee(uint56 mu0) private returns (uint56 mu) {
        address feeTo = CoinSwapFactory(factory).feeTo();
        mu=revisemu(uint192(reserve>>32));
        if (mu0>mu) _mint(feeTo, totalSupply.mul(uint(mu0-mu)) / (5*mu0+mu));
    }

    function mint(address to) external lock returns (uint liquidity) {
        uint224 circle = circleData;
        uint _totalSupply = totalSupply; 
        uint224 _reserve = reserve;
        uint96 reserve0 = uint96(_reserve >>128);
        uint96 reserve1 = uint96(_reserve >>32);
        uint scaledBalance0 = uint(IERC20(token0).balanceOf(address(this)))* uint56(circle >> 160);
        uint scaledBalance1 = uint(IERC20(token1).balanceOf(address(this)))* uint56(circle >> 104);
        require((scaledBalance0< 2**96) && (scaledBalance1< 2**96) 
            && ( scaledBalance0 >=10**16 || scaledBalance1 >=10**16), 'CSWP:7');
        if (_totalSupply == 0) { 
            uint lambda0 = uint16(circle >> 72);
            uint lambda1 = uint16(circle >> 56);
            liquidity = (scaledBalance0 * lambda0 + scaledBalance1 * lambda1) >> 1;
    	    revisemu(uint192((scaledBalance0<<96)|scaledBalance1));
        } else { 
            uint56 mu0=_mintFee(uint56(circle));
            _totalSupply = totalSupply;
    	    (uint mu, uint _totalS)=(0,0);
	        if (reserve0==0) {
	            mu=(uint(mu0) * reserve1) / scaledBalance1;
	            _totalS =  _totalSupply.mul(scaledBalance1)/reserve1;
	        } else if (reserve1==0) {
	            mu=(uint(mu0) * reserve0) / scaledBalance0;
	            _totalS = _totalSupply.mul(scaledBalance0)/reserve0;
	        } else {
	            (mu, _totalS) = (scaledBalance0 * reserve1) < (scaledBalance1 * reserve0)?
		        ((uint(mu0) * reserve0) / scaledBalance0, _totalSupply.mul(scaledBalance0)/reserve0) :
		        ((uint(mu0) * reserve1) / scaledBalance1, _totalSupply.mul(scaledBalance1)/reserve1) ;
	        }
            liquidity = _totalS - _totalSupply;
            circleData = (circle & 0xFF_FFFFFFFFFFFFFF_FFFFFFFFFFFFFF_FFFF_FFFF_FFFF_00000000000000) | uint224(mu);
        }
        _mint(to, liquidity);
        _update(scaledBalance0<<128 | scaledBalance1<<32 | uint32(_reserve));
        emit Mint(msg.sender, uint192((scaledBalance0-reserve0)<<96 | (scaledBalance1-reserve1)));
    }

    // this low-level function should be called from a contract which performs important safety checks
    // called when removing liquidity 
    function burn(address to) external lock returns (uint192 amount) {
        uint224 _reserve = reserve;
        address _token0 = token0;                                
        address _token1 = token1;    
        uint224 circle = circleData;
        uint scalar0 = uint56(circle >> 160);
        uint scalar1 = uint56(circle >> 104);
        _mintFee(uint56(circle));
        uint _totalSupply = totalSupply; 
        uint liquidity = balanceOf[address(this)];
        uint amount0 = liquidity.mul(uint96(_reserve>>128)) / (_totalSupply* scalar0 ); 
        uint amount1 = liquidity.mul(uint96(_reserve>>32)) / (_totalSupply* scalar1 ); 
        amount = uint192((amount0<<96)|amount1);
        require(amount > 0, 'CSWP:8');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        uint192 combinedBalance = uint192( uint(IERC20(_token0).balanceOf(address(this)))*scalar0  <<96 | uint(IERC20(_token1).balanceOf(address(this)))*scalar1 );
        _update(uint(combinedBalance)<<32 | uint32(_reserve));
        if (combinedBalance>0) revisemu(combinedBalance);
        emit Burn(msg.sender, amount, to); 
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amountOut, address to, bytes calldata data) external lock {       
        uint amount0Out = (amountOut >> 96); 
        uint amount1Out = uint(uint96(amountOut));
        uint scaledBalance0;
        uint scaledBalance1;
        uint _circleData = circleData;

        { // avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require((to != _token0) && (to != _token1), 'CSWP:9');
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            if (data.length > 0) ICoinSwapCallee(to).coinswapCall(msg.sender, amount0Out, amount1Out, data);
            scaledBalance0 = uint(IERC20(_token0).balanceOf(address(this)))* uint56(_circleData >> 160) ;
            scaledBalance1 = uint(IERC20(_token1).balanceOf(address(this)))* uint56(_circleData >> 104);
            require(scaledBalance0 < 2**96 && scaledBalance1 < 2**96, 'CSWP:10');
        }
        uint amountIn0;
        uint amountIn1;
        uint224 _reserve = reserve;
        {// if _reserve0 < amountOut, then should have been reverted above already, so no need to check here
            
            uint96 reserve0 = uint96(_reserve >>128);
            uint96 reserve1 = uint96(_reserve >>32);
            //amountIn0 = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
            //amountIn1 = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
            amountIn0 = scaledBalance0 + amount0Out * uint56(_circleData >> 160) - reserve0;
            amountIn1 = scaledBalance1 + amount1Out * uint56(_circleData >> 104) - reserve1;

            uint mulambda0 = uint(uint16(_circleData >> 72))*uint56(_circleData);
            uint mulambda1 = uint(uint16(_circleData >> 56))*uint56(_circleData);     
            uint X=mulambda0*(scaledBalance0*1000 - amountIn0*3); 
            uint Y=mulambda1*(scaledBalance1*1000 - amountIn1*3);
    	    require(10**37 > X && 10**37 >Y, 'CSWP:11');
            X = 10**37-X;
            Y = 10**37-Y;
            uint newrSquare = X*X+Y*Y;
            X=10**37-(mulambda0 * reserve0*1000);
            Y=10**37-(mulambda1 * reserve1*1000);
            require(newrSquare<= (X*X+Y*Y), 'CSWP:12');
        }
        _update(scaledBalance0<<128 | scaledBalance1<<32 | uint32(_reserve));
        emit Swap(msg.sender, uint192(amountIn0<<96 | amountIn1), uint192(amountOut), to);
        // in emit, the amountIn are scaled, but amountOut is not scaled
    }


    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; 
        address _token1 = token1; 
        uint224 _reserve = reserve;
        uint _circleData = circleData;
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this))-uint96(_reserve >>128)/uint56(_circleData >> 160)  );
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this))-uint96(_reserve >>32)/uint56(_circleData >> 104) );
	    revisemu(uint192(_reserve>>32));
    }

    // force reserves to match balances
    function sync() external lock {
        uint _circleData = circleData;
        _update( (IERC20(token0).balanceOf(address(this))*uint56(_circleData >> 160))  <<128 | (IERC20(token1).balanceOf(address(this))*uint56(_circleData >> 104))  <<32 | uint32(reserve));
    }
}


