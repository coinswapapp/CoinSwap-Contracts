//SPDX-License-Identifier: TBD
//revised from https://github.com/Uniswap/liquidity-staker/blob/master/contracts/StakingRewardsFactory.sol
//and https://github.com/Uniswap/liquidity-staker/blob/master/contracts/StakingRewards.sol
pragma solidity ^0.8.3;

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

contract StakingRewards {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    uint private reentryGuardCounter = 1;
    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    uint public periodFinish = 0;
    uint public rewardRate = 0;
    uint public rewardsDuration = 60 days;
    uint public lastUpdateTime;
    uint public rewardPerTokenStored;
    address public rewardsFactory;
    mapping(address => uint) public userRewardPerTokenPaid;
    mapping(address => uint) public rewards;
    uint public totalSupply;
    mapping(address => uint) public balanceOf;

    constructor(address _rewardsFactory, address _rewardsToken, address _stakingToken) {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsFactory = _rewardsFactory;
    }
    modifier onlyRewardsFactory() {
        require(msg.sender == rewardsFactory, "CSWPRW:10");
        _;
    }
    modifier nonReentrant() {
        reentryGuardCounter += 1;
        uint localCounter = reentryGuardCounter;
        _;
        require(localCounter == reentryGuardCounter, "CSWPRW:99");
    }
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish ;
    }
    function rewardPerToken() public view returns (uint) {
        if (totalSupply == 0) { return rewardPerTokenStored; }
        return rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18) / totalSupply );
    }
    function earned(address account) public view returns (uint) {
        return (balanceOf[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])) / 1e18).add(rewards[account]);
    }
    function getRewardForDuration() external view returns (uint) {
        return rewardRate.mul(rewardsDuration);
    }

    function stakeWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "CSWPRW:11");
        totalSupply = totalSupply.add(amount);
        balanceOf[msg.sender] = balanceOf[msg.sender].add(amount);
        ICoinSwapERC20(address(stakingToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function stake(uint amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "CSWPRW:11");
        totalSupply = totalSupply.add(amount);
        balanceOf[msg.sender] = balanceOf[msg.sender].add(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "CSWPRW:12");
        totalSupply = totalSupply.sub(amount);
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(balanceOf[msg.sender]);
        getReward();
    }

    function notifyRewardAmount(uint reward) external onlyRewardsFactory updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint remaining = periodFinish.sub(block.timestamp);
            uint leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover) / rewardsDuration;
        }
        uint balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= balance/rewardsDuration, "CSWPRW:13");
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    event RewardAdded(uint reward);
    event Staked(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event RewardPaid(address indexed user, uint reward);
}

contract StakingRewardsFactory {
    address public rewardsToken;
    uint public stakingRewardsGenesis;
    address[] public stakingTokens;
    address public owner;
    struct StakingRewardsInfo {
        address stakingRewards;
        uint rewardAmount;
    }
    mapping(address => StakingRewardsInfo) public stakingRewardsInfoByStakingToken;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address _rewardsToken, uint _stakingRewardsGenesis) {
        require(_stakingRewardsGenesis >= block.timestamp, 'CSWPRW:01');
        owner = msg.sender;
        rewardsToken = _rewardsToken;
        stakingRewardsGenesis = _stakingRewardsGenesis;
    }
    
    function transferOwnership(address newOwner) public {
        require(msg.sender == owner, "CSWPRW:02");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner; // to renounce owner, set newOwner = address(0)
    }

    function deploy(address stakingToken, uint rewardAmount) public {
        require(msg.sender == owner, "CSWPRW:02");
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingToken];
        require(info.stakingRewards == address(0), 'CSWPRW:03');

        info.stakingRewards = address(new StakingRewards(address(this), rewardsToken, stakingToken));
        info.rewardAmount = rewardAmount;
        stakingTokens.push(stakingToken);
    }

    function notifyRewardAmounts() public {
        require(stakingTokens.length > 0, 'CSWPRW:04');
        for (uint i = 0; i < stakingTokens.length; i++) {
            notifyRewardAmount(stakingTokens[i]);
        }
    }
    function notifyRewardAmount(address stakingToken) public {
        require(block.timestamp >= stakingRewardsGenesis, 'CSWPRW:05');
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingToken];
        require(info.stakingRewards != address(0), 'CSWPRW:06');
        if (info.rewardAmount > 0) {
            uint rewardAmount = info.rewardAmount;
            info.rewardAmount = 0;
            require(IERC20(rewardsToken).transfer(info.stakingRewards, rewardAmount), 'CSWPRW:07');
            StakingRewards(info.stakingRewards).notifyRewardAmount(rewardAmount);
        }
    }
}

interface ICoinSwapERC20 {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

library SafeMath {
    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "CSWPSM:01");
        return c;
    }
    function sub(uint a, uint b) internal pure returns (uint) {
        require(b <= a, "CSWPSM:02");
        uint c = a - b;
        return c;
    }
    function mul(uint a, uint b) internal pure returns (uint) {
        if (a == 0) { return 0; }
        uint c = a * b;
        require(c / a == b, "CSWPSM:03");
        return c;
    }
}

library SafeERC20 {
    using SafeMath for uint;
    function safeTransfer(IERC20 token, address to, uint value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }
    function safeTransferFrom(IERC20 token, address from, address to, uint value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }
    function safeApprove(IERC20 token, address spender, uint value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0), "CSWPSM:05");
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function safeIncreaseAllowance(IERC20 token, address spender, uint value) internal {
        uint newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }
    function safeDecreaseAllowance(IERC20 token, address spender, uint value) internal {
        uint newAllowance = token.allowance(address(this), spender).sub(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        uint size;
        address tokenAddress = address(token);
        assembly { size := extcodesize(tokenAddress) }
        require(size>0, "CSWPSM:06"); // requires token to be a contract address
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "CSWPSM:07");
        if (returndata.length > 0) { 
            require(abi.decode(returndata, (bool)), "CSWPSM:08");
        }
    }
}
