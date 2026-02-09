// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITreasury} from "../interfaces/ITreasury.sol";

contract Treasury is AccessControl, Pausable, ReentrancyGuard, ITreasury {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 private s_houseEdgeBps;
    mapping(address => uint256) private s_minBet;
    mapping(address => uint256) private s_maxBet;

    event HouseEdgeUpdated(uint256 bps);
    event BetLimitsUpdated(address indexed token, uint256 minBet, uint256 maxBet);
    event Payout(address indexed token, address indexed to, uint256 amount);
    event Collected(address indexed token, address indexed from, uint256 amount);

    constructor(address admin, uint256 houseEdgeBps) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
        s_houseEdgeBps = houseEdgeBps;
    }

    function getMinBet(address token) external view returns (uint256) {
        return s_minBet[token];
    }

    function getMaxBet(address token) external view returns (uint256) {
        return s_maxBet[token];
    }

    function getHouseEdgeBps() external view returns (uint256) {
        return s_houseEdgeBps;
    }

    function canPayout(address token, uint256 amount) external view returns (bool) {
        if (token == address(0)) {
            return address(this).balance >= amount;
        }
        return IERC20(token).balanceOf(address(this)) >= amount;
    }

    function payout(address token, address to, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        onlyRole(GAME_ROLE)
    {
        if (token == address(0)) {
            (bool ok, ) = to.call{value: amount}("" );
            if (!ok) {
                revert("ETH_PAYOUT_FAILED");
            }
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit Payout(token, to, amount);
    }

    function collect(address token, address from, uint256 amount)
        external
        payable
        whenNotPaused
        onlyRole(GAME_ROLE)
    {
        if (token == address(0)) {
            if (msg.value != amount) {
                revert("INVALID_ETH_AMOUNT");
            }
        } else {
            if (msg.value != 0) {
                revert("NO_ETH_ALLOWED");
            }
            IERC20(token).safeTransferFrom(from, address(this), amount);
        }
        emit Collected(token, from, amount);
    }

    function setMinMaxBet(address token, uint256 minBet, uint256 maxBet) external onlyRole(MANAGER_ROLE) {
        if (minBet > maxBet) {
            revert("INVALID_LIMITS");
        }
        s_minBet[token] = minBet;
        s_maxBet[token] = maxBet;
        emit BetLimitsUpdated(token, minBet, maxBet);
    }

    function setHouseEdgeBps(uint256 bps) external onlyRole(MANAGER_ROLE) {
        s_houseEdgeBps = bps;
        emit HouseEdgeUpdated(bps);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    receive() external payable {}
}
