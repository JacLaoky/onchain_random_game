// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IRandomnessProvider} from "../interfaces/IRandomnessProvider.sol";
import {IRandomnessConsumer} from "../interfaces/IRandomnessConsumer.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IGame} from "../interfaces/IGame.sol";

contract DiceGame is AccessControl, Pausable, ReentrancyGuard, IRandomnessConsumer, IGame {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct Bet {
        address player;
        address token;
        uint256 amount;
        uint256 target;
        uint256 requestId;
        bool resolved;
        uint256 payout;
    }

    ITreasury public immutable treasury;
    IRandomnessProvider public immutable randomnessProvider;

    uint256 public nextBetId = 1;
    mapping(uint256 => Bet) public bets;
    mapping(uint256 => uint256) public requestToBet;

    event BetPlaced(uint256 indexed betId, address indexed player, address token, uint256 amount, uint256 target);
    event BetResolved(uint256 indexed betId, address indexed player, uint256 payout, bool win);

    constructor(address admin, ITreasury treasuryAddress, IRandomnessProvider provider) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        treasury = treasuryAddress;
        randomnessProvider = provider;
    }

    function placeBet(address token, uint256 amount, uint256 target)
        public
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 betId)
    {
        if (target < 2 || target > 98) {
            revert("INVALID_TARGET");
        }
        treasury.collect{value: msg.value}(token, msg.sender, amount);
        betId = nextBetId++;
        uint256 requestId = randomnessProvider.requestRandomness(1);
        bets[betId] = Bet({
            player: msg.sender,
            token: token,
            amount: amount,
            target: target,
            requestId: requestId,
            resolved: false,
            payout: 0
        });
        requestToBet[requestId] = betId;
        emit BetPlaced(betId, msg.sender, token, amount, target);
    }

    function placeBet(address token, uint256 amount, bytes calldata data)
        external
        payable
        returns (uint256 betId)
    {
        uint256 target = abi.decode(data, (uint256));
        return placeBet(token, amount, target);
    }

    function getBet(uint256 betId)
        external
        view
        returns (address player, address token, uint256 amount, bool resolved)
    {
        Bet storage bet = bets[betId];
        return (bet.player, bet.token, bet.amount, bet.resolved);
    }

    function rawFulfillRandomness(uint256 requestId, uint256[] calldata randomWords) external whenNotPaused {
        if (msg.sender != address(randomnessProvider)) {
            revert("ONLY_PROVIDER");
        }
        uint256 betId = requestToBet[requestId];
        Bet storage bet = bets[betId];
        if (bet.resolved) {
            revert("BET_RESOLVED");
        }
        uint256 roll = (randomWords[0] % 100) + 1;
        bool win = roll < bet.target;
        uint256 payout = 0;
        if (win) {
            uint256 houseEdgeBps = treasury.getHouseEdgeBps();
            uint256 rawPayout = (bet.amount * 100) / (bet.target - 1);
            payout = (rawPayout * (10_000 - houseEdgeBps)) / 10_000;
            treasury.payout(bet.token, bet.player, payout);
        }
        bet.resolved = true;
        bet.payout = payout;
        emit BetResolved(betId, bet.player, payout, win);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
