//SPDX-License-Identifier: TBD
//adapted from https://github.com/Uniswap/governance/blob/master/contracts/TreasuryVester.sol
pragma solidity ^0.7.4;

contract TreasuryVester {
    address public cswp;
    address public recipient;

    uint public vestingAmount;
    uint public vestingBegin;
    uint public vestingCliff;
    uint public vestingEnd;

    uint public lastUpdate;

    constructor(
        address cswp_,
        address recipient_,
        uint vestingAmount_,
        uint vestingBegin_,
        uint vestingCliff_,
        uint vestingEnd_
    ) {
        require(vestingBegin_ >= block.timestamp, 'TreasuryVester::constructor: vesting begin too early');
        require(vestingCliff_ >= vestingBegin_, 'TreasuryVester::constructor: cliff is too early');
        require(vestingEnd_ > vestingCliff_, 'TreasuryVester::constructor: end is too early');

        cswp = cswp_;
        recipient = recipient_;

        vestingAmount = vestingAmount_;
        vestingBegin = vestingBegin_;
        vestingCliff = vestingCliff_;
        vestingEnd = vestingEnd_;

        lastUpdate = vestingBegin;
    }

    function setRecipient(address recipient_) public {
        require(msg.sender == recipient, 'TreasuryVester::setRecipient: unauthorized');
        recipient = recipient_;
    }

    function claim() public {
        require(block.timestamp >= vestingCliff, 'TreasuryVester::claim: not time yet');
        uint amount;
        if (block.timestamp >= vestingEnd) {
            amount = ICSWPToken(cswp).balanceOf(address(this));
        } else {
            uint claimPeriod = block.timestamp - lastUpdate;
            uint z = vestingAmount*claimPeriod;
            require(claimPeriod == 0 || z / claimPeriod == vestingAmount, 'TreasuryVester:OverFlow');
            amount = z/(vestingEnd - vestingBegin);
            lastUpdate = block.timestamp;
        }
        ICSWPToken(cswp).transfer(recipient, amount);
    }
}

interface ICSWPToken {
    function balanceOf(address account) external view returns (uint);
    function transfer(address dst, uint rawAmount) external returns (bool);
}
