// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasury {
    function getMinBet(address token) external view returns (uint256);
    function getMaxBet(address token) external view returns (uint256);
    function getHouseEdgeBps() external view returns (uint256);
    function canPayout(address token, uint256 amount) external view returns (bool);

    function payout(address token, address to, uint256 amount) external;
    function collect(address token, address from, uint256 amount) external;
}
