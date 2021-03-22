// SPDX-License-Identifier: TBD
pragma solidity 0.7.4;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, 'SafeMath: addition overflow');
        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, 'SafeMath: subtraction overflow');
    }
    function sub(uint256 a,uint256 b,string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }
}

contract CSWPToken {
    using SafeMath for uint;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    string public constant name = 'CoinSwap Governance';
    string public constant symbol= 'CSWP';
    uint8 public constant decimals = 18;
    mapping (address => uint) public nonces;
    uint public totalSupply = 1_000_000_000e18; // initial 1 billion CSWP
    uint public mintingAllowedAfter;
    uint32 public constant minimumTimeBetweenMints = 1 days * 365;
    uint8 public constant mintCap = 2;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address payable public owner;
    mapping (address => address) public delegates;
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;
    mapping (address => uint32) public numCheckpoints;


    bytes32 public constant DOMAIN_TYPEHASH = keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
    bytes32 public DOMAIN_SEPARATOR;

    constructor() {
        owner = tx.origin;
        balanceOf[tx.origin] = totalSupply; // initial 1 billion 
        mintingAllowedAfter = block.timestamp;
        uint chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)),keccak256(bytes('1')), chainId, address(this)));
    }

    function setNewOwner(address payable newOwner) public {//renounce owner by setting newOwner = 0
        require(owner == msg.sender, 'ERC20: requires owner');
        owner = newOwner;
        emit OwnershipTransferred(owner, newOwner);
    }

    function mint(address dst, uint amount) external {
        require(owner == msg.sender, 'CSWP: not owner');
        require(block.timestamp >= mintingAllowedAfter, "CSWP: minting not allowed yet");
        require(dst != address(0), "CSWP: cannot transfer to the zero address");

        mintingAllowedAfter = block.timestamp + minimumTimeBetweenMints;
        require(amount <= (totalSupply * mintCap)/100, "CSWP: exceeded mint cap"); 
        totalSupply = totalSupply+amount;
        balanceOf[dst] = balanceOf[dst] + amount;
        emit Transfer(address(0), dst, amount);
        _moveDelegates(address(0), delegates[dst], amount);
    }

    function allowances(address account, address spender) external view returns (uint) {
        return allowance[account][spender];
    }

    function burn(address from, uint value) external {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        _moveDelegates(delegates[from], address(0), value);
        emit Transfer(from, address(0), value);
    }

    function approve(address spender, uint amount) external returns (bool) {
        require(amount <= balanceOf[msg.sender]);
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function permit(address sender, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'ERC20: expired');
        require(value <= balanceOf[sender]);
        bytes32 digest = keccak256(
            abi.encodePacked('\x19\x01',DOMAIN_SEPARATOR,keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[sender]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == sender, 'ERC20: wrong signature');
        allowance[sender][spender] = value;
        emit Approval(sender, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        _moveDelegates(delegates[from], delegates[to], value);
        emit Transfer(from, to, value);
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (msg.sender != from) {
            uint newAllowance = allowance[from][msg.sender].sub(value);
            allowance[from][msg.sender] = newAllowance;
            emit Approval(from, msg.sender, newAllowance);
        }
        _transfer(from, to, value);
        return true;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint delegatorBalance = balanceOf[delegator];
        delegates[delegator] = delegatee;
        emit DelegateChanged(delegator, currentDelegate, delegatee);
        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    function delegateBySig(address delegatee,uint nonce,uint expiry,uint8 v,bytes32 r, bytes32 s) external {
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH,delegatee,nonce,expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01",DOMAIN_SEPARATOR,structHash));
        address deletator = ecrecover(digest, v, r, s);
        require(deletator != address(0), "CSWP: invalid signature");
        require(nonce == nonces[deletator]++, "CSWP: invalid nonce");
        require(block.timestamp <= expiry, "CSWP: signature expired");
        return _delegate(deletator, delegatee);
    }

    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    function getPriorVotes(address account, uint blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "CSWP: too early");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) { return 0; }

        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; 
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint256 oldVotes, uint256 newVotes) internal {
        uint blockNumber = block.number;
        require(blockNumber<2**32, 'block.number overflow');
        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(uint32(blockNumber), newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }
        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

}
