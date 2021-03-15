//SPDX-License-Identifier: TBD
pragma solidity =0.7.4;

import './CoinSwapPair.sol';  

contract CoinSwapFactory {
    address payable public feeTo;
    address payable public feeToSetter;
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address payable _feeToSetter) {
        feeToSetter = _feeToSetter;
        feeTo = _feeToSetter;
    }
    
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB, uint224 circle) external returns (address pair) {  
        require(tx.origin==feeToSetter, 'CSWP:22');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(getPair[token0][token1] == address(0), 'CSWP:20'); 
        require(uint16(circle>>56)>0 && uint16(circle>>72)>0 && 
                uint16(circle>>88)>0 && uint16(circle>>88)<=9999
                && uint56(circle>>104)>=1 && uint56(circle>>104)<=10**16
                && uint56(circle>>160)>=1 && uint56(circle>>160)<=10**16, 'CSWP:23');
        bytes memory bytecode = type(CoinSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        CoinSwapPair(pair).initialize(token0, token1, circle);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; 
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
    
    function setFeeTo(address payable _feeTo) external {
	    require(msg.sender == feeToSetter, 'CSWP:21');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address payable _feeToSetter) external {
        require(msg.sender == feeToSetter, 'CSWP:22');
        feeToSetter = _feeToSetter;
    }
}
