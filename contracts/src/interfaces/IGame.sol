// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IGame {
    function placeBet(address token, uint256 amount, bytes calldata data) external payable returns (uint256 betId);

    function getBet(uint256 betId)
        external
        view
        returns (address player, address token, uint256 amount, bool resolved);
}
