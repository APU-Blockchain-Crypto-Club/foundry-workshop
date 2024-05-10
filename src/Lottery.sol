// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

contract Lottery is VRFConsumerBaseV2, ConfirmedOwner {
    event TicketPurchased(address indexed buyer, uint256 indexed ticketId);
    event WinnerDrawn(
        uint256 indexed requestId,
        address indexed winner,
        uint256 amount
    );
    event PrizeClaimed(uint256 indexed requestId, address indexed claimant);

    VRFCoordinatorV2Interface private vrfCoordinator;
    bytes32 private keyHash;
    uint32 private callbackGasLimit = 100000;
    uint16 private requestConfirmations = 3;
    uint32 private numWords = 1;
    uint64 private subscriptionId;

    struct LotteryRound {
        address[] participants;
        address winner;
        uint256 endTime;
        uint256 prizeAmount;
        bool prizeClaimed;
    }

    // Mapping from request ID to LotteryRound
    mapping(uint256 => LotteryRound) public lotteries;
    // Global list of all registered participants (ever participated)
    address[] public allParticipants;
    // Mapping to check if address is already added to allParticipants
    mapping(address => bool) private registeredParticipants;

    uint256 public ticketPrice = 0.01 ether;
    uint256 private lastRequestId;

    constructor(
        uint64 _subscriptionId
    )
        VRFConsumerBaseV2(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625)
        ConfirmedOwner(msg.sender)
    {
        vrfCoordinator = VRFCoordinatorV2Interface(
            0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625
        );
        subscriptionId = _subscriptionId;
        keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
    }

    function buyTicket() public payable {
        require(msg.value == ticketPrice, "Incorrect payment");
        LotteryRound storage round = lotteries[lastRequestId];
        round.participants.push(msg.sender);
        // Add to global participants list if not already registered
        if (!registeredParticipants[msg.sender]) {
            registeredParticipants[msg.sender] = true;
            allParticipants.push(msg.sender);
        }
        emit TicketPurchased(msg.sender, round.participants.length);
    }

    function startLottery() external onlyOwner {
        lastRequestId = vrfCoordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        lotteries[lastRequestId] = LotteryRound({
            participants: new address[](0),
            winner: address(0),
            endTime: block.timestamp + 24 hours,
            prizeAmount: 0,
            prizeClaimed: false
        });
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        LotteryRound storage round = lotteries[_requestId];
        require(block.timestamp >= round.endTime, "Lottery not ended yet");
        require(round.winner == address(0), "Winner already drawn");

        uint256 winnerIndex = _randomWords[0] % round.participants.length;
        round.winner = round.participants[winnerIndex];
        round.prizeAmount = address(this).balance;
        emit WinnerDrawn(_requestId, round.winner, round.prizeAmount);
    }

    function claimPrize(uint256 _requestId) external {
        LotteryRound storage round = lotteries[_requestId];
        require(msg.sender == round.winner, "Not the winner");
        require(!round.prizeClaimed, "Prize already claimed");

        payable(msg.sender).transfer(round.prizeAmount);
        round.prizeClaimed = true;
        emit PrizeClaimed(_requestId, msg.sender);
    }

    function getLotteryInfo(
        uint256 _requestId
    ) external view returns (LotteryRound memory) {
        return lotteries[_requestId];
    }

    function getAllParticipants() external view returns (address[] memory) {
        return allParticipants;
    }
}
