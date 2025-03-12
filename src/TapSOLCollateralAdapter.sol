// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./interfaces/ITapSOLToken.sol";
import "./PythSOLPriceOracle.sol";

/**
 * @title TapSOLCollateralAdapter
 * @dev Contract for using tapSOL as collateral in DeFi applications
 */
contract TapSOLCollateralAdapter {
    // Custom errors
    error CallerNotAdmin();
    // The tapSOL token contract
    ITapSOLToken public immutable tapSOL;

    // Oracle for SOL price in USD
    address public solPriceOracle;

    // Collateralization ratio (100% = 10000)
    uint256 public collateralRatio;

    // Administrator address
    address public admin;

    /**
     * @dev Modifier to ensure only the admin can call certain functions
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, CallerNotAdmin());
        _;
    }

    /**
     * @dev Constructor to initialize the collateral adapter
     * @param _tapSOL Address of the tapSOL token contract
     * @param _solPriceOracle Address of the SOL price oracle
     * @param _collateralRatio Initial collateralization ratio
     */
    constructor(address _tapSOL, address _solPriceOracle, uint256 _collateralRatio) {
        tapSOL = ITapSOLToken(_tapSOL);
        solPriceOracle = _solPriceOracle;
        collateralRatio = _collateralRatio;
        admin = msg.sender;
    }

    /**
     * @dev Returns the USD value of the given amount of tapSOL
     * @param amount The amount of tapSOL
     * @return The equivalent value in USD
     */
    function getCollateralValueInUSD(uint256 amount) public view returns (uint256) {
        // Get the SOL value of tapSOL
        uint256 solValue = tapSOL.getSolValue(amount);

        // Get the SOL price in USD from the oracle (placeholder)
        uint256 solPriceInUSD = getSolPriceInUSD();

        // Calculate the USD value
        return (solValue * solPriceInUSD) / 1e18;
    }

    /**
     * @dev Returns the maximum loan amount for the given amount of tapSOL collateral
     * @param collateralAmount The amount of tapSOL collateral
     * @return The maximum loan amount in USD
     */
    function getMaxLoanAmount(uint256 collateralAmount) external view returns (uint256) {
        uint256 collateralValueInUSD = getCollateralValueInUSD(collateralAmount);
        return (collateralValueInUSD * 10_000) / collateralRatio;
    }

    /**
     * @dev Sets the SOL price oracle address
     * @param _solPriceOracle The new SOL price oracle address
     */
    function setSolPriceOracle(address _solPriceOracle) external onlyAdmin {
        solPriceOracle = _solPriceOracle;
    }

    /**
     * @dev Sets the collateralization ratio
     * @param _collateralRatio The new collateralization ratio
     */
    function setCollateralRatio(uint256 _collateralRatio) external onlyAdmin {
        collateralRatio = _collateralRatio;
    }

    /**
     * @dev Returns the SOL price in USD from the Pyth oracle
     * @return The SOL price in USD
     */
    function getSolPriceInUSD() internal view returns (uint256) {
        // Call the PythSOLPriceOracle to get the SOL price in USD
        return PythSOLPriceOracle(solPriceOracle).getSolPriceInUSD();
    }

    /**
     * @dev Sets the admin address
     * @param newAdmin The new admin address
     */
    function setAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }
}
