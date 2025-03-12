// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Deploy} from "script/Deploy.sol";
import {console} from "forge-std/console.sol";
import {TapSOLToken} from "../src/TapSOLToken.sol";
import {TapSOLRate} from "../src/TapSOLRate.sol";
import {TapSOLCollateralAdapter} from "../src/TapSOLCollateralAdapter.sol";
import {PythSOLPriceOracle} from "../src/PythSOLPriceOracle.sol";
import {IPythOracle} from "../src/interfaces/IPythOracle.sol";

contract DeployTapSOL is Deploy {
    string constant CONFIG_PATH = "/deployments/tapSOL.json";
    string constant TOKEN_KEY = "TapSOLToken";
    string constant RATE_KEY = "TapSOLRate";
    string constant COLLATERAL_ADAPTER_KEY = "TapSOLCollateralAdapter";
    string constant PRICE_ORACLE_KEY = "PythSOLPriceOracle";

    address public constant PYTH_ORACLE_ADDRESS =
        0x2880aB155794e7179c9eE2e38200202908C17B43; // Pyth Oracle on Monad Testnet
    bytes32 public constant SOL_PRICE_FEED_ID =
        0xef0d8b6fda2ceba41da15d4095d1da392a0d2f8ed0c6c7bc0f4cfac8c280b56d; // SOL/USD feed
    uint256 public constant MAX_STALENESS = 3600;

    address public constant WORMHOLE_ADDRESS = 0xBB73cB66C26740F31d1FabDC6b7A46a038A300dd; // Wormhole
    bytes32 public constant TAPSOL_POOL_ACCOUNT =
        0x0000000000000000000000000000000000000000000000000000000000000001;
    uint256 public constant ALLOWED_UPDATE_STALENESS = 3600;
    uint256 public constant ALLOWED_RATE_STALENESS = 7200;
    uint256 public constant COLLATERAL_RATIO = 12_500;

    constructor() Deploy(1, testnetEnabled(true)) {}

    function testnetEnabled(bool testnet) internal pure returns (bool) {
        return testnet;
    }

    function run() external {
        setUp();

        vm.startBroadcast(deployerPrivateKey);

        PythSOLPriceOracle pythSOLPriceOracle =
            new PythSOLPriceOracle(PYTH_ORACLE_ADDRESS, SOL_PRICE_FEED_ID, MAX_STALENESS);

        TapSOLRate tapSOLRate = new TapSOLRate(
            WORMHOLE_ADDRESS,
            TAPSOL_POOL_ACCOUNT,
            ALLOWED_UPDATE_STALENESS,
            ALLOWED_RATE_STALENESS
        );

        TapSOLToken tapSOLToken = new TapSOLToken(DEPLOYER, DEPLOYER);
        tapSOLToken.setRateOracle(address(tapSOLRate));

        TapSOLCollateralAdapter tapSOLCollateralAdapter = new TapSOLCollateralAdapter(
            address(tapSOLToken), address(pythSOLPriceOracle), COLLATERAL_RATIO
        );

        vm.stopBroadcast();

        // Store deployment addresses
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, CONFIG_PATH);

        writeAddress(path, TOKEN_KEY, address(tapSOLToken));
        writeAddress(path, RATE_KEY, address(tapSOLRate));
        writeAddress(path, COLLATERAL_ADAPTER_KEY, address(tapSOLCollateralAdapter));
        writeAddress(path, PRICE_ORACLE_KEY, address(pythSOLPriceOracle));

        // Verify contract connections
        verifyContractConnections(
            address(tapSOLToken),
            address(tapSOLRate),
            address(tapSOLCollateralAdapter),
            address(pythSOLPriceOracle)
        );

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("PythSOLPriceOracle: ", address(pythSOLPriceOracle));
        console.log("TapSOLRate: ", address(tapSOLRate));
        console.log("TapSOLToken: ", address(tapSOLToken));
        console.log("TapSOLCollateralAdapter: ", address(tapSOLCollateralAdapter));
        console.log("Deployer: ", DEPLOYER);
        console.log("===========================\n");
    }

    function verifyContractConnections(
        address tokenAddress,
        address rateAddress,
        address collateralAdapterAddress,
        address priceOracleAddress
    )
        internal
        view
    {
        TapSOLToken token = TapSOLToken(tokenAddress);
        TapSOLRate rate = TapSOLRate(rateAddress);
        TapSOLCollateralAdapter collateralAdapter =
            TapSOLCollateralAdapter(collateralAdapterAddress);
        PythSOLPriceOracle priceOracle = PythSOLPriceOracle(priceOracleAddress);

        console.log("\n=== Verifying Contract Connections ===");

        address configuredRateOracle = address(token.rateOracle());
        bool isRateOracleSet = configuredRateOracle == rateAddress;
        if (!isRateOracleSet) {
            console.log("  Expected:", rateAddress);
            console.log("  Actual:  ", configuredRateOracle);
        }

        address configuredTapSOL = address(collateralAdapter.tapSOL());
        bool isTapSOLSet = configuredTapSOL == tokenAddress;
        if (!isTapSOLSet) {
            console.log("  Expected:", tokenAddress);
            console.log("  Actual:  ", configuredTapSOL);
        }

        address configuredPriceOracle = collateralAdapter.solPriceOracle();
        bool isPriceOracleSet = configuredPriceOracle == priceOracleAddress;
        if (!isPriceOracleSet) {
            console.log("  Expected:", priceOracleAddress);
            console.log("  Actual:  ", configuredPriceOracle);
        }

        bool isDeployerRateUpdater = rate.authorizedRateUpdaters(DEPLOYER);
        bool isDeployerPriceOracleAdmin = priceOracle.admin() == DEPLOYER;
        bool isDeployerCollateralAdapterAdmin = collateralAdapter.admin() == DEPLOYER;
        bool isDeployerTokenOwner = token.owner() == DEPLOYER;

        // Verify all expected connections
        bool allConnectionsVerified = isRateOracleSet && isTapSOLSet && isPriceOracleSet
            && isDeployerRateUpdater && isDeployerPriceOracleAdmin
            && isDeployerCollateralAdapterAdmin && isDeployerTokenOwner;

        if (allConnectionsVerified) console.log("All connections verified successfully");
        else console.log("WARNING: Some connections were not properly established!");
    }
}
