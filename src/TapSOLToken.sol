// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TapSOLRate} from "./TapSOLRate.sol";
import {ITapSOLToken} from "./interfaces/ITapSOLToken.sol";
import {NTTToken} from "./ntt/NTToken.sol";

/**
 * @title TapSOLToken
 * @dev Implementation of the tapSOL token as a Native Transfer Token (NTT)
 * This token represents tapSOL from Solana on Monad
 */
/// @custom:security-contact security@nuts.finance
contract TapSOLToken is ITapSOLToken, NTTToken {
    // Events
    event TokensBurned(address indexed account, uint256 amount, uint256 rate);

    // Error messages
    error RateOracleNotSet();
    error ZeroAddress();
    error UnauthorizedBurn(address caller);

    TapSOLRate public rateOracle;

    /**
     * @dev Constructor to initialize the tapSOL token
     * @param owner Address of the initial owner
     * @param minter Address of the minter
     */
    constructor(address owner, address minter) NTTToken(owner, minter) {}

    /**
     * @dev Returns the current exchange rate of tapSOL in terms of SOL
     * @return The exchange rate scaled to 1e18
     */
    function getExchangeRate() external view returns (uint256) {
        return rateOracle.getRate();
    }

    /**
     * @dev Calculates the SOL value of the given amount of tapSOL
     * @param amount The amount of tapSOL
     * @return The equivalent value in SOL
     */
    function getSolValue(uint256 amount) external view returns (uint256) {
        return (amount * rateOracle.getRate()) / (10 ** decimals());
    }

    /**
     * @dev Sets the rate oracle address
     * @param _rateOracle Address of the TapSOLRate oracle contract
     */
    function setRateOracle(address _rateOracle) external onlyOwner {
        rateOracle = TapSOLRate(_rateOracle);
    }

    /**
     * @dev Override burn to add permission control
     * Only the minter (NTT contract) should be able to burn tokens
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) public override onlyMinter {
        super.burn(amount);
        if (address(rateOracle) == address(0)) revert RateOracleNotSet();
        emit TokensBurned(msg.sender, amount, rateOracle.getRate());
    }

    /**
     * @dev Override burnFrom to add permission control
     * Only the minter (NTT contract) should be able to burn tokens
     * @param account The account to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) public override onlyMinter {
        super.burnFrom(account, amount);
        if (address(rateOracle) == address(0)) revert RateOracleNotSet();
        emit TokensBurned(account, amount, rateOracle.getRate());
    }
}
