// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract Lottery is VRFV2WrapperConsumerBase, ConfirmedOwner {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(
        uint256 requestId,
        uint256[] randomWords,
        uint256 payment
    );

    event TicketPurchased(address indexed buyer, uint256 indexed ticketId);
    event WinnerDrawn(
        uint256 indexed requestId,
        address indexed winner,
        uint256 amount
    );
    event PrizeClaimed(uint256 indexed requestId, address indexed claimant);

    error PaymentInsufficient();
    error InvalidRoundID();
    error LotteryEnded();
    error RandomValueNotReceived();
    error LotteryNotEnded();
    error NotWinner();

    uint32 private callbackGasLimit = 100000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;

    // Address LINK - hardcoded for Sepolia
    address linkAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    // address WRAPPER - hardcoded for Sepolia
    address wrapperAddress = 0xab18414CD93297B0d12ac29E63Ca20f515b3DB46;

    struct LotteryRound {
        address[] participants;
        address winner;
        uint256 endTime;
        uint256 prizeAmount;
        bool prizeClaimed;
        uint256 paid; // amount paid in link
        bool fulfilled; // whether the request has been successfully fulfilled by the VRF
        uint256 randomValue; // the random value returned by the VRF
    }

    //Array of all lottery round IDs
    uint256[] public lotteryRoundIds;
    // Mapping from round ID to LotteryRound
    mapping(uint256 => LotteryRound) public lotteries;

    uint256 public ticketPrice = 0.01 ether;
    uint256 private lastRequestId;

    constructor()
        VRFV2WrapperConsumerBase(linkAddress, wrapperAddress)
        ConfirmedOwner(msg.sender)
    {}

    function buyTicket(uint256 _roundID) public payable {
        if (lotteries[_roundID].endTime == 0) {
            revert InvalidRoundID();
        }
        if (msg.value != ticketPrice) {
            revert PaymentInsufficient();
        }
        if (lotteries[_roundID].endTime < block.timestamp) {
            revert LotteryEnded();
        }
        LotteryRound storage round = lotteries[_roundID];
        round.participants.push(msg.sender);

        emit TicketPurchased(msg.sender, round.participants.length);
    }

    function createLottery() external onlyOwner returns (uint256 roundID) {
        roundID = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );
        lotteries[roundID] = LotteryRound({
            participants: new address[](0),
            winner: address(0),
            endTime: block.timestamp + 1 minutes,
            prizeAmount: 0.01 ether,
            prizeClaimed: false,
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomValue: 0,
            fulfilled: false
        });

        lotteryRoundIds.push(roundID);
        emit RequestSent(roundID, numWords);
        return roundID;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        LotteryRound storage round = lotteries[_requestId];

        //ensure the roundID is valid
        if (round.endTime == 0) {
            revert InvalidRoundID();
        }

        round.fulfilled = true;
        round.randomValue = _randomWords[0];

        emit RequestFulfilled(_requestId, _randomWords, round.paid);
        emit WinnerDrawn(_requestId, round.winner, round.prizeAmount);
    }

    function chooseWinner(uint256 _roundID) external onlyOwner {
        LotteryRound storage round = lotteries[_roundID];
        if (round.endTime == 0) {
            revert InvalidRoundID();
        }
        if (!round.fulfilled) {
            revert RandomValueNotReceived();
        }
        if (round.endTime > block.timestamp) {
            revert LotteryNotEnded();
        }

        uint256 winnerIndex = round.randomValue % round.participants.length;
        round.winner = round.participants[winnerIndex];

        round.prizeAmount = address(this).balance;
        round.prizeClaimed = true;
        emit PrizeClaimed(_roundID, round.winner);
    }

    function claimPrize(uint256 _roundID) external {
        LotteryRound storage round = lotteries[_roundID];
        if (round.endTime == 0) {
            revert InvalidRoundID();
        }
        if (round.endTime < block.timestamp) {
            revert LotteryEnded();
        }
        if (round.winner != msg.sender) {
            revert NotWinner();
        }

        payable(msg.sender).transfer(round.prizeAmount);
        round.prizeClaimed = true;
        emit PrizeClaimed(_roundID, msg.sender);
    }

    function getLotteryInfo(
        uint256 _requestId
    ) external view returns (LotteryRound memory) {
        return lotteries[_requestId];
    }

    function getAllLotteryRoundIds() external view returns (uint256[] memory) {
        return lotteryRoundIds;
    }
}
