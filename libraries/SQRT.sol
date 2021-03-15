//SPDX-License-Identifier: TBD
pragma solidity =0.7.4;

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SQRT {
    function sqrt(uint256 a) internal pure returns (uint256 x) { 
        if (a > 3) {
            uint msbpos =0;
            uint b=a;
            if (b > 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
                msbpos += 128;
                b = b >> 128;
            } 
            if (b > 0xFFFFFFFFFFFFFFFF) {
                msbpos += 64;
                b = b>>64;
            }
            if (b > 0xFFFFFFFF ) {
                msbpos += 32;
                b = b>>32;
            }
            if (b > 0xFFFF ) {
                msbpos += 16;
                b = b>>16;
            }
            if (b > 0xFF ) {
                msbpos += 8;
                b = b>>8;
            }
            if (b > 0xF ) {
                msbpos += 4;
            }
            msbpos += 2;
            
            uint256 x0=a;
            uint X=((a >> 1) + 1);
            uint Y=2**(msbpos/2);
            x0 = X< Y ? X : Y;
            while (x < x0 ) {
                x0 = x;
                x = (a / x0 + x0) >> 1;
            }
        } else if (a != 0) {
            x = 1;
        }
    }
}

