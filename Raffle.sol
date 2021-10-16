// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.6;

import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

contract Raffle is VRFConsumerBase{
    //identifies which chainlink oracle to use
    bytes32 internal s_keyHash;
    //LINK oracle fee
    uint256 internal s_fee;
    
    struct Participant{
        address participantAddress;
        bool enteredInRaffle;                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           bool lostLastRaffle;
        uint currentMultiplier;
        uint currentWeight;
        uint amountWagered;
    }
    
    uint16 private maxParticipants;
    uint8 private maxEntriesPerRaffle;
    
    uint16 private minParticipantsRequired;
    
    uint private costPerEntry;
    uint private maxTotalPool;
    uint private currentPool;
    
    //base weight of all raffle entries
    uint8 private constant baseWeight = 100;
    
    //summed weight for later random calculation
    uint public totalWeight;
    
    //winning roll
    uint public randomRoll;
    
    //set the amount to modify after losing
    uint8 private losingMultiplierIncrease;
    uint8 private maxMultiplier;
    
    //default multiplier to reset to
    uint8 private constant baseMultiplier = 0;
    
    address public winningAddress;
    address payable private raffleOwner;
    mapping(address => Participant) private allParticipants;
    Participant[] public currentParticipants; 
    
    //VRFcoordinator = 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9
    //LINK address = 0xa36085F69e2889c224210F603D836748e7dC0088
    //keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4
    
    event RafflePicking();
    event RafflePicked(address indexed winner);
    event RaffleEntered(address indexed participant);
    
    
    //constructor(address _vrfCoordinator, address _link, bytes32 keyHash, uint256 fee) VRFConsumerBase(_vrfCoordinator, _link) public {
    constructor() VRFConsumerBase(0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9, 0xa36085F69e2889c224210F603D836748e7dC0088) public {
        //s_keyHash = keyHash;
        s_keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
        //s_fee = fee;
        s_fee = 0.1 * 10 ** 18; //0.1 LINK
        
        maxParticipants = 1000;
        
        //all currency is represented by wei unless specified: 1 ether == 1e18
        //FOR TESTING ON KOVAN, 10 gwei
        costPerEntry = 250000000000000000 wei;
        
        //FOR TESTING ON JSVM
        //costPerEntry = 1 ether;
        
        //as of 5-13-21 9:31 AM value of 1 eth is $3,877.65
        maxTotalPool = 1000 ether;
        
        minParticipantsRequired = 2;
        
        //translates to % in the raffle calculation by losingMultiplierIncrease + baseWeight
        losingMultiplierIncrease = 1;
        
        maxMultiplier = 10;
        
        raffleOwner = msg.sender;
    }
    
    function EnterRaffle() public payable {
        require(msg.value >= costPerEntry, "Minimum amount of ether not met to enter raffle");
        Participant storage sender = allParticipants[msg.sender];
        require(currentParticipants.length <= maxParticipants, "Maximum particpants already");
        require(!sender.enteredInRaffle, "Already in raffle");
        require(msg.value + currentPool <= maxTotalPool, "Raffle pool too large");
        
        //add entry fee to pool
        currentPool += msg.value;
        
        //new overall user to raffle game. 
        if(sender.participantAddress != msg.sender){
            sender.participantAddress = msg.sender;
        }
        
        //enter user in currentRaffle
        sender.enteredInRaffle = true;
        
        emit RaffleEntered(sender.participantAddress);

        //track amount wagered, in case of paypack
        sender.amountWagered = msg.value;
        
        //check if user has entered in previous raffle and lost
        if(sender.lostLastRaffle && sender.currentMultiplier <= maxMultiplier){
            //additive multiplier, eg increase by 1% each time, losingMultiplierIncrease = 1;
            sender.currentMultiplier += losingMultiplierIncrease;
        }
        
        //add user to current pool of participants
        currentParticipants.push(sender);
    }
    
    function getRandomNumber() internal returns (bytes32 requestId){
        return requestRandomness(s_keyHash, s_fee);
    }
    
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomRoll = randomness.mod(totalWeight);
        PickWinner();
    }
    
    function PickWinner() private{
        Participant memory winner;
        for(uint i=0;i<currentParticipants.length;i++){
            if(currentParticipants[i].currentWeight >= randomRoll){
                winner = currentParticipants[i];
                emit RafflePicked(winner.participantAddress);
                winningAddress = winner.participantAddress;
                
                //reset winner winning multiplier to base
                winner.currentMultiplier = baseMultiplier;
                winner.lostLastRaffle = false;
                break;
            }
        }

        //update records of all participants
        for(uint i=0;i<currentParticipants.length;i++){
            if(winner.participantAddress != currentParticipants[i].participantAddress){
                currentParticipants[i].lostLastRaffle = true;
            }
            currentParticipants[i].enteredInRaffle = false;
            //currentParticipants[i].currentWeight = 0;
            allParticipants[currentParticipants[i].participantAddress] = currentParticipants[i];
        }
        uint winAmount = currentPool;
        //reset pool
        currentPool = 0;
        //pay winner
        payable(winner.participantAddress).transfer(winAmount);
       
        //reset participants
        delete currentParticipants;
        assert(currentParticipants.length == 0);
    }
    
    function DrawRaffle() public{
        //TODO: Test on javaVM with 1000+ iterations
        require(LINK.balanceOf(address(this)) >= s_fee, "Not enough LINK to pay fee");
        require(msg.sender == raffleOwner, "Not raffle owner");
        require(currentParticipants.length >= minParticipantsRequired, "Not enough participants to raffle");
        
        totalWeight = 0;
        randomRoll = 0;
        for(uint i=0; i<currentParticipants.length;i++){
            //add user's multiplier to the total weight of the drawing
            totalWeight += currentParticipants[i].currentMultiplier + baseWeight;
            
            //set the weight of the user to the total weight + their multiplier for later calculating winner
            currentParticipants[i].currentWeight = totalWeight;
        }

        //Generate random weight
        emit RafflePicking();
        getRandomNumber();
        
    }

    function DestroyContract() public{
        require(msg.sender == raffleOwner, "Not raffle owner");
        
        //transfer all unused funds from active participants back to them
        for(uint i=0; i<currentParticipants.length; i++){
            payable(currentParticipants[i].participantAddress).transfer(currentParticipants[i].amountWagered);
        }
        //transfer all LINK back to owner
        LINK.transfer(raffleOwner, LINK.balanceOf(address(this)));
        
        //transfer any remaining
        selfdestruct(raffleOwner);
    }
    
    
}