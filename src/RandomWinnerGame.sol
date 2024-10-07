// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "chainlink-develop/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "chainlink-develop/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import "chainlink-develop/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import "chainlink-develop/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

error GameAlreadyStarted();
error InvalidMaxPlayers();
error GameNotStarted();
error IncorrectEntryFee(uint256 sent, uint256 required);
error GameFull(uint256 currentPlayers, uint256 maxPlayers);
error InsufficientLINK(uint256 balance, uint256 required);
error FailedToSend();



contract RandomWinnerGame is VRFV2PlusWrapperConsumerBase, ConfirmedOwner {
    //events emiitted when game starts
    event GameStarted(uint256 gameId, uint8 maxPlayers, uint256 entryFee);
    //events emiitted when someone joins a game
    event PlayerJoined(uint256 gameId, address player);
    //events emitted when the game ends
    event GameEnded(uint256 gameId, address winner, uint256 requestId);

    //Chainlink varianbles
    //The amount of LINK to send with the request
    uint256 public fee;
    //ID of public key against which randomness is generated
    bytes32 public keyHash;

    uint32 public callbackGasLimit = 100000;

    uint16 public requestConfirmations = 3;

    //num of random values to retrieve in one request; VRFV2Wrapper.getConfig().maxNumWords.
    uint32 public numWords = 1;

    //Address LINK- hardcoded for sepolia
    address public linkAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    //address WRAPPER- hardcoded for sepolia
    address public wrapperAddress = 0x195f15F2d49d693cE265b4fB0fdDbE15b1850Cc1;

    //address of the players
    address[] public players;

    //max number of players in one game
    uint8 maxPlayers;

    //variable to indicate if the game has started or not
    bool public gameStarted;

    //the fees for entering the game
    uint256 entryFee;

    //current game id
    uint256 public gameId;

    constructor() ConfirmedOwner(msg.sender) VRFV2PlusWrapperConsumerBase(wrapperAddress) {}

    //startGame starts the game by setting appr values for variables
    function startGame(uint8 _maxPlayers, uint256 _entryFee) public onlyOwner {
        //check if game has started
        if (gameStarted) {
            revert GameAlreadyStarted();
        }

        //check if maxPlayers is greater than 0
        if(_maxPlayers == 0) {
            revert InvalidMaxPlayers();
        }

        //empty players array
        delete players;

        //set the max players for this game
        maxPlayers = _maxPlayers;

        //set the game started to true
        gameStarted = true;

        //setup the entryFee for the game
        entryFee = _entryFee;
        
        gameId += 1;

        emit GameStarted(gameId, maxPlayers, entryFee);
    }

    //joinGame; when a player wants to enter the game
    function joinGame() public payable {
        //check if a game is already running
        if(!gameStarted) {
            revert GameNotStarted();
        }

        //check if the value inputted equals the entry fee
        if (msg.value != entryFee) {
            revert IncorrectEntryFee(msg.value, entryFee);
        }

        //check if the game has space to add another player
        if (players.length >= maxPlayers) {
            revert GameFull(players.length, maxPlayers);
        }

        //add the sender to the players list
        players.push(msg.sender);

        emit PlayerJoined(gameId, msg.sender);

        //if the list is full, start the winner selection process
        if (players.length == maxPlayers) {
            getRandomWinner();
        }
    }

    //receives and stores random values with contract
    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        uint256 winnerIndex = _randomWords[0] % players.length;

        //get the address of the winner from the players array
        address winner = players[winnerIndex];

        //send the ether in the contract to the winner
        (bool sent, ) = winner.call{value: address(this).balance}("");
        if(!sent) {
            revert FailedToSend();
        }

        emit GameEnded(gameId, winner, _requestId);

        //set the gameStarted variable to false
        gameStarted = false;
    }

    //takes specified parameters andsubmits requests to the VRF v2.5 Wrapper contract
    function requestRandomWords() private returns (uint256) {
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
            VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
        );
        uint256 requestId;
        uint256 reqPrice;

        //requestRandomness is a function within VRFV2PlusWrapperConsumerBase
        //starts the process of randomness generation
        (requestId, reqPrice) = requestRandomness(
            callbackGasLimit, requestConfirmations, numWords, extraArgs
        );

        return requestId;
    }

    //getRandomWinner ; starteds the process of selecting a winner
    function getRandomWinner() private returns (uint256 requestId) {
        //using LINK as interface for Link token
        LinkTokenInterface LINK = LinkTokenInterface(linkAddress);
        
        uint256 currentBalance = LINK.balanceOf(address(this));
        if (currentBalance < fee) {
            revert InsufficientLINK(currentBalance, fee);
        }

        return requestRandomWords();
    }

    receive() external payable {}

    fallback() external payable {}

}