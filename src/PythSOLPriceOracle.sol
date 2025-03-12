// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./interfaces/IPythOracle.sol";

/**
 * @title PythSOLPriceOracle
 * @dev Implementation of a price oracle for SOL using Pyth Network
 */
contract PythSOLPriceOracle {
    // Custom errors
    error CallerNotAdmin();
    error PriceFeedTooStale();
    error NegativePrice();
    // The Pyth Oracle contract
    IPythOracle public immutable pythOracle;

    // SOL price feed ID in Pyth
    bytes32 public immutable solPriceFeedId;

    // Maximum staleness allowed for the price feed
    uint256 public maxStaleness;

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
     * @dev Constructor to initialize the SOL price oracle
     * @param _pythOracle Address of the Pyth Oracle contract
     * @param _solPriceFeedId ID of the SOL price feed in Pyth
     * @param _maxStaleness Maximum staleness allowed for the price feed (in seconds)
     */
    constructor(address _pythOracle, bytes32 _solPriceFeedId, uint256 _maxStaleness) {
        pythOracle = IPythOracle(_pythOracle);
        solPriceFeedId = _solPriceFeedId;
        maxStaleness = _maxStaleness;
        admin = msg.sender;
    }

    /**
     * @dev Returns the latest SOL price in USD
     * @return The SOL price in USD, normalized to 18 decimals
     */
    function getSolPriceInUSD() external view returns (uint256) {
        (int64 price,, int32 expo, uint256 publishTime) =
            pythOracle.getPriceWithMetadata(solPriceFeedId);

        // Check price staleness
        require(block.timestamp - publishTime <= maxStaleness, PriceFeedTooStale());

        // Check price is positive
        require(price > 0, NegativePrice());

        uint256 adjustedPrice;
        if (expo < 0) {
            // Convert the negative exponent to a positive multiplier
            uint256 multiplier = 10 ** uint256(-int256(expo) + 18);
            adjustedPrice = uint256(int256(price)) * multiplier;
        } else {
            // Divide by the positive exponent to get to base units, then multiply to 1e18
            uint256 divisor = 10 ** uint256(int256(expo));
            adjustedPrice = uint256(int256(price)) / divisor;
            adjustedPrice = adjustedPrice * (10 ** 18);
        }

        return adjustedPrice;
    }

    /**
     * @dev Updates the SOL price feed with the latest data from Pyth
     * @param updateData The encoded price update data
     */
    function updateSolPriceFeed(bytes calldata updateData) external payable {
        bytes32[] memory priceFeedIds = new bytes32[](1);
        priceFeedIds[0] = solPriceFeedId;

        bytes[] memory updateDataArray = new bytes[](1);
        updateDataArray[0] = updateData;

        pythOracle.updatePriceFeeds{value: msg.value}(priceFeedIds, updateDataArray);
    }

    /**
     * @dev Sets the maximum staleness allowed for the price feed
     * @param _maxStaleness The new maximum staleness (in seconds)
     */
    function setMaxStaleness(uint256 _maxStaleness) external onlyAdmin {
        maxStaleness = _maxStaleness;
    }

    /**
     * @dev Sets the admin address
     * @param newAdmin The new admin address
     */
    function setAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }
}
