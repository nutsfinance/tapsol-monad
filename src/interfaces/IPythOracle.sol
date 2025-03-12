// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IPythOracle
 * @dev Interface for Pyth Oracle price feeds
 */
interface IPythOracle {
    /**
     * @dev Returns the latest price of the requested asset
     * @param assetId The ID of the asset to query the price for
     * @return The price of the asset in USD
     */
    function getPrice(bytes32 assetId) external view returns (uint256);

    /**
     * @dev Returns the latest price with additional metadata
     * @param assetId The ID of the asset to query the price for
     * @return price The price of the asset
     * @return conf The confidence interval
     * @return expo The exponent (to determine decimal places)
     * @return publishTime The timestamp when the price was published
     */
    function getPriceWithMetadata(bytes32 assetId)
        external
        view
        returns (int64 price, uint64 conf, int32 expo, uint256 publishTime);

    /**
     * @dev Updates the price feed with the latest data from Pyth
     * @param assetIds The IDs of the assets to update
     * @param data The encoded price update data
     */
    function updatePriceFeeds(
        bytes32[] calldata assetIds,
        bytes[] calldata data
    )
        external
        payable;
}
