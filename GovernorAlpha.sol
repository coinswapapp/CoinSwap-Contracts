//SPDX-License-Identifier: TBD
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

// adapted from FROM https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/GovernorAlpha.sol
// Copyright 2020 Compound Labs, Inc.
// report: https://forum.openzeppelin.com/t/compound-alpha-governance-system-audit/2376

contract GovernorAlpha {
    string public constant name = "CoinSwap Governor";
    function quorumVotes() public pure returns (uint) { return 40_000_000e18; } // 4% of CSWP
    function proposalThreshold() public pure returns (uint) { return 10_000_000e18; } // 1% of CSWP
    function proposalMaxOperations() public pure returns (uint) { return 10; } // 10 actions
    function votingDelay() public pure returns (uint) { return 1; } // 1 block
    function votingPeriod() public pure returns (uint) { return 40_320; } // ~7 days in blocks (assuming 15s blocks)
    TimelockInterface public timelock;
    CSWPInterface public cswp;// governance token

    uint public proposalCount=0;
    struct Proposal {
        uint id;
        address proposer;
        uint eta; // time for the proposal to be available for execution, set once the vote succeeds
        address[] targets;//the ordered list of target addresses for calls to be made
        uint[] values; // The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        string[] signatures; // The ordered list of function signatures to be called
        bytes[] calldatas; // The ordered list of calldata to be passed to each call
        uint startBlock; // The block at which voting begins: holders must delegate their votes prior to this block
        uint endBlock; // The block at which voting ends: votes must be cast prior to this block
        uint forVotes;
        uint againstVotes;
        bool canceled;
        bool executed;
        //mapping (address => Receipt) receipts; // Receipts of ballots for the entire set of voters
    }
    struct Receipt {
        bool hasVoted; // Whether or not a vote has been cast
        bool support;
        uint votes;
    }
    mapping (address => mapping (uint => Receipt)) receipts;
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    Proposal[] public proposals;
    mapping (address => uint) public latestProposalIds;
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,bool support)");

    event ProposalCreated(uint id, address proposer, address[] targets, uint[] values, string[] signatures, bytes[] calldatas, uint startBlock, uint endBlock, string description);
    event VoteCast(address voter, uint proposalId, bool support, uint votes);
    event ProposalCanceled(uint id);
    event ProposalQueued(uint id, uint eta);
    event ProposalExecuted(uint id);

    constructor(address _timelock, address _cswp) {
        timelock = TimelockInterface(_timelock);
        cswp = CSWPInterface(_cswp);
    }

    function propose(address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) public returns (uint pID) {
        require(cswp.getPriorVotes(msg.sender, block.number - 1) > proposalThreshold(), "CSWP-Gov:01");
        require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "CSWP-Gov:02");
        require(targets.length != 0, "GovernorAlpha: must provide actions");
        require(targets.length <= proposalMaxOperations(), "GovernorAlpha: too many actions");

        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
          ProposalState proposersLatestProposalState = state(latestProposalId);
          require(proposersLatestProposalState != ProposalState.Active, "CSWP-Gov:03");
          require(proposersLatestProposalState != ProposalState.Pending, "CSWP-Gov:04");
        }
        proposals.push();
        pID = proposalCount;
        proposals[pID].id= pID;
        proposals[pID].proposer = msg.sender;
        proposals[pID].eta= 0;
        proposals[pID].targets=targets;
        proposals[pID].values =values;
        proposals[pID].signatures= signatures;
        proposals[pID].calldatas =calldatas;
        proposals[pID].startBlock= block.number+votingDelay();
        proposals[pID].endBlock= proposals[pID].startBlock+votingPeriod();
        proposals[pID].forVotes= 0;
        proposals[pID].againstVotes= 0;
        proposals[pID].canceled= false;
        proposals[pID].executed= false;
        latestProposalIds[msg.sender] = proposalCount;
        emit ProposalCreated(pID, msg.sender, targets, values, signatures, calldatas, proposals[pID].startBlock, proposals[pID].endBlock, description);
        proposalCount++;
    }

    function queue(uint proposalId) public {
        require(state(proposalId) == ProposalState.Succeeded, "CSWP-Gov:05");
        Proposal storage proposal = proposals[proposalId];
        proposal.eta = block.timestamp + timelock.delay();
        for (uint i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalQueued(proposalId, proposal.eta);
    }

    function _queueOrRevert(address target, uint value, string memory signature, bytes memory data, uint eta) internal {
        require(!timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))), "CSWP-Gov:06");
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function execute(uint proposalId) public payable {
        require(state(proposalId) == ProposalState.Queued, "CSWP-Gov:07");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction{value: proposal.values[i]}(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalExecuted(proposalId);
    }

    function getActions(uint proposalId) public view returns (address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas) {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    function getReceipt(uint proposalId, address voter) public view returns (Receipt memory) {
        return receipts[voter][proposalId];
        //return proposals[proposalId].receipts[voter];
    }

    function getblockNumber() public view returns (uint dd) {
        dd=block.number;
    }

    function state(uint proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId >= 0, "CSWP-Gov:08");
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes()) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= proposal.eta+timelock.GRACE_PERIOD()) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    function cancel(uint proposalId) public {
        ProposalState stateOfId = state(proposalId);
        require(stateOfId != ProposalState.Executed, "CSWP-Gov:09");

        Proposal storage proposal = proposals[proposalId];
        require(cswp.getPriorVotes(proposal.proposer, block.number-1) < proposalThreshold(), "CSWP-Gov:10");

        proposal.canceled = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalCanceled(proposalId);
    }
    function castVote(uint proposalId, bool support) public {
        return _castVote(msg.sender, proposalId, support);
    }

    function castVoteBySig(uint proposalId, bool support, uint8 v, bytes32 r, bytes32 s) public {
        uint chainId;
        assembly { chainId := chainid() }
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), chainId, address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "CSWP-Gov:11");
        return _castVote(signatory, proposalId, support);
    }

    function _castVote(address voter, uint proposalId, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "CSWP-Gov:12");
        Proposal storage proposal = proposals[proposalId];
        //Receipt storage receipt = proposal.receipts[voter];
        Receipt storage receipt = receipts[voter][proposalId];
        require(receipt.hasVoted == false, "CSWP-Gov:13");
        uint votes = cswp.getPriorVotes(voter, proposal.startBlock);

        if (support) {
            proposal.forVotes += votes;
            require(proposal.forVotes>votes, 'CSWP-Gov:14');
        } else {
            proposal.againstVotes += votes;
            require(proposal.againstVotes>votes, 'CSWP-Gov:15');
        }
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;
        emit VoteCast(voter, proposalId, support, votes);
    }
}

interface TimelockInterface {
    function delay() external view returns (uint);
    function GRACE_PERIOD() external view returns (uint);
    function acceptAdmin() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external returns (bytes32);
    function cancelTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external;
    function executeTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external payable returns (bytes memory);
}
interface CSWPInterface {
    function getPriorVotes(address account, uint blockNumber) external view returns (uint);
}
