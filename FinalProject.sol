// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "zk-merkle-tree/contracts/ZKTree.sol";

contract Voting is ZKTree {
    uint voting_choice;
    address public organizer;
    mapping (address => uint) deposit; // keep track of voters of how much they deposit
    mapping (address => uint) deposit_used_for_voting; // keep track if the deposit is enough for voting
    mapping (bytes32 => address) committed_vote; // voter have to hashed their vote in commited phase, with h(vote, nonce)
    mapping ( uint => uint ) voting_count;
    uint elected_vote;
    uint deployedBlockNumber;

    // Phase 0: Amir got to choose the number of choice
    constructor(uint _choice,  uint32 _levels, IHasher _hasher, IVerifier _verifier)
    ZKTree(_levels, _hasher, _verifier) {
        
        voting_choice = _choice; // Amir got to choose how many choice
        deployedBlockNumber = block.number;
        organizer = msg.sender;

        for(uint i = 1; i <= _choice; i++){
            voting_count[i] = 0;
        }
    }

    // Phase 1: Sign up and deposit phase (t0~t1)
    function signUp() public payable { 
        require(block.number > deployedBlockNumber && block.number <= deployedBlockNumber+300); // make sure they register within the first 60 minutes
        require(msg.value == 1 ether, "You need to deposit 1 ether"); // require the deposit to this contract is 1 ether
        deposit[msg.sender] += 1 ether; // keep track on how many votes this voter has
        
    }

    // Phase 2 (t1~t2)
    function committingVote(bytes32 _hashvalue) public {
        require(block.number > deployedBlockNumber+300 && block.number <= deployedBlockNumber+600); // make sure they commit within the second 60 minutes
        require(deposit_used_for_voting[msg.sender] < deposit[msg.sender]);

        // the hashvalue is the hash(vote, nonce), where nonce is a signicantly long string -> no one knows other's vote before reveal phase
        // vote should be within the range of {1, 2, ... k}
        require(committed_vote[_hashvalue] == address(0), "This vote and nonce has been used");
        committed_vote[_hashvalue] = msg.sender;
        _commit(_hashvalue);
        deposit_used_for_voting[msg.sender] += 1; // record that the voter used 1 ether for voting

    }

    // Phase 3 (t2~t3)
    function revealingVote( 
        uint _choice,
        uint256 _nullifier,
        uint256 _root,
        uint[2] memory _proof_a,
        uint[2][2] memory _proof_b,
        uint[2] memory _proof_c) public {
            require(block.number > deployedBlockNumber+600 && block.number <= deployedBlockNumber+900); // make sure they reveal their vote within the third 60 minutes
            require(_choice > 0 && _choice <= voting_choice, "Invalid option!");
            _nullify(
                bytes32(_nullifier),
                bytes32(_root),
                _proof_a,
                _proof_b,
                _proof_c
            );
            // the _nullify function could return "The nullifier has been submitted", which means the some have already voted for this proof
            // or it may return "invalid proof" which indicates that the proof provide can't proof that the voter knows a particular hash value in the committed_vote, which are stored in _commit

        voting_count[_choice] += 1;
        if(voting_count[_choice] > voting_count[elected_vote]){
            elected_vote = _choice;
        }

    }

    // Phase 4(t3 and beyond)
    bool reentrancy_lock = false; // to prevent reentrancy attack
    function withdraw() public {
        require(block.number > deployedBlockNumber+900); // after block.number > 900, everyone can withdraw
        require(reentrancy_lock == false); // required that no one is keep using this function
        reentrancy_lock = true;
        address payable recipient = payable(msg.sender);
        require(deposit[recipient] > 0);
        recipient.call{value: deposit[recipient]}(""); //pay the sale value to the previous owner
        deposit[recipient] = 0;
        reentrancy_lock = false;

    }

}