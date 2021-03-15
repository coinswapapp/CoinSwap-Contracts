//SPDX-License-Identifier: TBD
pragma solidity >=0.7.4;

interface ICoinSwapCallee {
    function coinswapCall(address sender, uint amount0,uint amount1, bytes calldata data) external;
}