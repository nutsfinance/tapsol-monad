// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

/**
 * @title ITapSOLToken
 * @dev Interface for the tapSOL token contract
 */
interface ITapSOLToken {
    /**
     * @dev Returns the current exchange rate of tapSOL in terms of SOL
     * @return The exchange rate scaled to 1e18
     */
    function getExchangeRate() external view returns (uint256);

    /**
     * @dev Calculates the SOL value of the given amount of tapSOL
     * @param amount The amount of tapSOL
     * @return The equivalent value in SOL
     */
    function getSolValue(uint256 amount) external view returns (uint256);
}
