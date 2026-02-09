// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract GameRegistry is AccessControl, Pausable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(address => bool) private s_enabled;
    address[] private s_games;

    event GameEnabled(address indexed game, bool enabled);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    function setGameEnabled(address game, bool enabled) external onlyRole(MANAGER_ROLE) {
        s_enabled[game] = enabled;
        if (enabled) {
            s_games.push(game);
        }
        emit GameEnabled(game, enabled);
    }

    function isGameEnabled(address game) external view returns (bool) {
        return s_enabled[game];
    }

    function listGames() external view returns (address[] memory) {
        return s_games;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
