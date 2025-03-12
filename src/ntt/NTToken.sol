// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from
    "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {BaseToken} from "./BaseToken.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

abstract contract NTTToken is BaseToken, ERC20Burnable, Ownable {
    error CallerNotMinter(address caller);
    error InvalidMinterZeroAddress();

    event NewMinter(address newMinter);

    address public minter;

    modifier onlyMinter() {
        if (msg.sender != minter) revert CallerNotMinter(msg.sender);
        _;
    }

    constructor(
        address initialOwner,
        address _minter
    )
        BaseToken("tapSOL", "TSL")
        Ownable(initialOwner)
    {
        minter = _minter;
    }

    function mint(address _account, uint256 _amount) external onlyMinter {
        _mint(_account, _amount);
    }

    function setMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0), InvalidMinterZeroAddress());
        minter = newMinter;
        emit NewMinter(newMinter);
    }

    function _update(
        address from,
        address to,
        uint256 value
    )
        internal
        override(ERC20, BaseToken)
    {
        return BaseToken._update(from, to, value);
    }
}
