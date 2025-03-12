// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {stdJson} from "forge-std/StdJson.sol";
import {console} from "forge-std/console.sol";
import {Config} from "script/Config.sol";

abstract contract Deploy is Config {
    string Path;

    constructor(uint256 _networkCount, bool _testnet) Config(_networkCount, _testnet) {
        if (_testnet) Path = "/deployments/..";
    }

    function writeAddress(
        string memory path,
        string memory name,
        address value
    )
        internal
    {
        vm.writeJson(vm.serializeAddress("contracts", name, value), path);
    }

    function getAddress(string memory name) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, Path, name, ".json");
        bytes memory addr = vm.parseJson(vm.readFile(path), ".address");
        return abi.decode(addr, (address));
    }
}
