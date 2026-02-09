// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IRandomnessProvider} from "../interfaces/IRandomnessProvider.sol";
import {IRandomnessConsumer} from "../interfaces/IRandomnessConsumer.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";

contract LotteryGame is AccessControl, Pausable, ReentrancyGuard, IRandomnessConsumer {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct Round {
        uint256 id;
        uint256 closeTime;
        address token;
        uint256 ticketPrice;
        uint256 pot;
        bool closed;
        bool settled;
        address winner;
        uint256 requestId;
    }

    ITreasury public immutable treasury;
    IRandomnessProvider public immutable randomnessProvider;

    uint256 public activeRoundId;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => address[]) private s_entries;
    mapping(uint256 => uint256) public requestToRound;

    event RoundOpened(uint256 indexed roundId, address token, uint256 ticketPrice, uint256 closeTime);
    event TicketsPurchased(uint256 indexed roundId, address indexed player, uint256 count, uint256 totalCost);
    event RoundClosed(uint256 indexed roundId, uint256 requestId);
    event RoundSettled(uint256 indexed roundId, address indexed winner, uint256 payout);

    constructor(address admin, ITreasury treasuryAddress, IRandomnessProvider provider) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        treasury = treasuryAddress;
        randomnessProvider = provider;
    }

    function openRound(address token, uint256 ticketPrice, uint256 closeTime) external onlyRole(MANAGER_ROLE) {
        uint256 roundId = activeRoundId + 1;
        activeRoundId = roundId;
        rounds[roundId] = Round({
            id: roundId,
            closeTime: closeTime,
            token: token,
            ticketPrice: ticketPrice,
            pot: 0,
            closed: false,
            settled: false,
            winner: address(0),
            requestId: 0
        });
        emit RoundOpened(roundId, token, ticketPrice, closeTime);
    }

    function buyTickets(address token, uint256 ticketPrice, uint256 count)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 roundId)
    {
        roundId = activeRoundId;
        Round storage round = rounds[roundId];
        if (round.closed) {
            revert("ROUND_CLOSED");
        }
        if (block.timestamp >= round.closeTime) {
            revert("ROUND_EXPIRED");
        }
        if (round.token != token || round.ticketPrice != ticketPrice) {
            revert("ROUND_MISMATCH");
        }
        uint256 totalCost = ticketPrice * count;
        treasury.collect{value: msg.value}(token, msg.sender, totalCost);
        round.pot += totalCost;
        for (uint256 i = 0; i < count; i++) {
            s_entries[roundId].push(msg.sender);
        }
        emit TicketsPurchased(roundId, msg.sender, count, totalCost);
    }

    function closeRound() external whenNotPaused onlyRole(MANAGER_ROLE) {
        uint256 roundId = activeRoundId;
        Round storage round = rounds[roundId];
        if (round.closed) {
            revert("ALREADY_CLOSED");
        }
        round.closed = true;
        uint256 requestId = randomnessProvider.requestRandomness(1);
        round.requestId = requestId;
        requestToRound[requestId] = roundId;
        emit RoundClosed(roundId, requestId);
    }

    function rawFulfillRandomness(uint256 requestId, uint256[] calldata randomWords) external whenNotPaused {
        if (msg.sender != address(randomnessProvider)) {
            revert("ONLY_PROVIDER");
        }
        uint256 roundId = requestToRound[requestId];
        Round storage round = rounds[roundId];
        if (round.settled) {
            revert("ROUND_SETTLED");
        }
        address[] storage entries = s_entries[roundId];
        if (entries.length == 0) {
            round.settled = true;
            emit RoundSettled(roundId, address(0), 0);
            return;
        }
        uint256 winnerIndex = randomWords[0] % entries.length;
        address winner = entries[winnerIndex];
        round.winner = winner;
        round.settled = true;
        treasury.payout(round.token, winner, round.pot);
        emit RoundSettled(roundId, winner, round.pot);
    }

    function getEntries(uint256 roundId) external view returns (address[] memory) {
        return s_entries[roundId];
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
