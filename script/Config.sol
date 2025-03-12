// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

abstract contract Config is Script {
    bool testnet;
    uint256 deployerPrivateKey;
    address DEPLOYER;

    string[] public rpcs;
    uint32[] public chainIds;
    uint256[] public forks;

    constructor(uint256 _networkCount, bool _testnet) {
        forks = new uint256[](_networkCount);
        rpcs = new string[](_networkCount);
        chainIds = new uint32[](_networkCount);

        testnet = _testnet;

        if (testnet) {
            /// rpcs and chainIds for testnet should be added here
            /// based on network count

            rpcs[0] = "MONAD_TESTNET_RPC";

            chainIds[0] = 10_143; // Monad Testnet
        } else {
            /// rpcs and chainIds for mainnet should be added here
            /// based on network count
        }
    }

    function setUp() internal {
        if (vm.envUint("DEV_PRIV_KEY") == 0) revert("No private keys found");
        deployerPrivateKey = vm.envUint("DEV_PRIV_KEY");
        DEPLOYER = vm.addr(deployerPrivateKey);
    }
}
