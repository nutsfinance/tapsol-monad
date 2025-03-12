// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TapSOLToken} from "../src/TapSOLToken.sol";
import {TapSOLRate} from "../src/TapSOLRate.sol";
import {WormholeMock} from "wormhole-solidity-sdk/testing/helpers/WormholeMock.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";

contract TapSOLTokenTest is Test {
    TapSOLToken public tapSOLToken;
    TapSOLRate public tapSOLRate;
    WormholeMock public wormholeMock;

    address owner = address(0x1);
    address minter = address(0x2);
    address user1 = address(0x3);
    address user2 = address(0x4);

    bytes32 mockTapSOLPoolAccount =
        0x048a3e08c3b495be17f45427d89bec5b80c7e2695c1864d76743db39bed346d6;
    uint256 THIRTY_MINUTES = 60 * 30;
    uint256 THIRTY_DAYS = 60 * 60 * 24 * 30;

    // Mock Wormhole data
    bytes mockDevnetResponse =
        hex"010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000073010000002a01000104000000660000000966696e616c697a656400000000000000000000000000000000000000000000011a02048a3e08c3b495be17f45427d89bec5b80c7e2695c1864d76743db39bed346d606a7d51718c774c928566398691d5eb68b5eb8a39b4b6d5c73555b210000000001000104000001dd000000000e8a333900060fbc482645c089cb4c158a7c669dfe20bef457ae808d671dc9a32f28cbc4b1f0ad3d406ea9380200000000004e7b9000000000000000000006814ed4caf68a174672fdac86031a63e84ea15efa1d44b72293f6dbdb0016500000011a01451e3dd50d3b7b8536045c2b7ac2ec259473ebc25ae3bcbe1fbeb17d52fbc7be0d095d453d5883bfeeb42269657a79abd0ed08bb66f986591ce4f00f950bd5c85a1fcd5de2beec843fe794ddc95faf466d40451c9faa569e7822d92c7e6ae13afd23e07509baddedfdb516a90b9197bb504743255d0e37c5ff5dce8a241eedc4319ea768fedf644c8aae9b8e2188add06bc550fbf716c822b9ce63c7783d952e1ffcd141e9832caf10ad917495ca0f271b5b293cd47027ea737007ed40eb39a0bd09e6a3feecf99032e1c1df6b9722dcb3634e7b8e3440936bc34b0cc1c8eb521f06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9c2dba43ab1ac1800eb5e0a9753bf16003402000000000000000000000011d78000000000000001690006a7d5171875f729c73d93408f216120067ed88c76e08c287fc1946000000000000000283c338a0e000000002af7af65000000003402000000000000350200000000000021cdb16500000000";
    uint256 constant MOCK_GUARDIAN_PRIVATE_KEY =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    uint8 sigGuardianIndex = 0;

    uint64 mockBlockTime = 1_706_151_199_000_000;

    event TokensBurned(address indexed account, uint256 amount, uint256 rate);

    function setUp() public {
        vm.warp(mockBlockTime / 1_000_000);
        vm.startPrank(owner);

        wormholeMock = new WormholeMock();
        tapSOLRate = new TapSOLRate(
            address(wormholeMock), mockTapSOLPoolAccount, THIRTY_MINUTES, THIRTY_DAYS
        );
        tapSOLToken = new TapSOLToken(owner, minter);
        tapSOLToken.setRateOracle(address(tapSOLRate));

        // Initialize with mock data
        bytes32 responseDigest = tapSOLRate.getResponseDigest(mockDevnetResponse);
        (uint8 sigV, bytes32 sigR, bytes32 sigS) =
            vm.sign(MOCK_GUARDIAN_PRIVATE_KEY, responseDigest);

        IWormhole.Signature[] memory signatures = new IWormhole.Signature[](1);
        signatures[0] = IWormhole.Signature({
            r: sigR,
            s: sigS,
            v: sigV,
            guardianIndex: sigGuardianIndex
        });

        tapSOLRate.updatePool(mockDevnetResponse, signatures);

        vm.stopPrank();
    }

    function test_Constructor() public view {
        assertEq(tapSOLToken.name(), "tapSOL");
        assertEq(tapSOLToken.symbol(), "TSL");
        assertEq(tapSOLToken.decimals(), 18);
        assertEq(tapSOLToken.owner(), owner);
        assertEq(tapSOLToken.minter(), minter);
    }

    function test_MintTokens() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.startPrank(minter);
        tapSOLToken.mint(user1, mintAmount);
        vm.stopPrank();

        assertEq(tapSOLToken.balanceOf(user1), mintAmount);
        assertEq(tapSOLToken.totalSupply(), mintAmount);
    }

    function test_MintOnlyMinter() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        vm.expectRevert();
        tapSOLToken.mint(user1, mintAmount);
        vm.stopPrank();

        assertEq(tapSOLToken.balanceOf(user1), 0);
        assertEq(tapSOLToken.totalSupply(), 0);
    }

    function test_BurnTokens() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 burnAmount = 400 * 10 ** 18;
        vm.startPrank(minter);

        tapSOLToken.mint(minter, mintAmount);
        tapSOLRate.getRate();
        tapSOLToken.burn(burnAmount);

        vm.stopPrank();

        assertEq(tapSOLToken.balanceOf(minter), mintAmount - burnAmount);
        assertEq(tapSOLToken.totalSupply(), mintAmount - burnAmount);
    }

    function test_BurnTokensFromUser() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 burnAmount = 400 * 10 ** 18;

        vm.startPrank(minter);
        tapSOLToken.mint(user1, mintAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        tapSOLToken.approve(minter, burnAmount);
        vm.stopPrank();

        vm.startPrank(minter);
        tapSOLRate.getRate();
        tapSOLToken.burnFrom(user1, burnAmount);
        vm.stopPrank();

        assertEq(tapSOLToken.balanceOf(user1), mintAmount - burnAmount);
        assertEq(tapSOLToken.totalSupply(), mintAmount - burnAmount);
    }

    function test_BurnOnlyMinter() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 burnAmount = 400 * 10 ** 18;

        vm.startPrank(minter);
        tapSOLToken.mint(user1, mintAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        tapSOLToken.burn(burnAmount);
        vm.stopPrank();

        assertEq(tapSOLToken.balanceOf(user1), mintAmount);
        assertEq(tapSOLToken.totalSupply(), mintAmount);
    }

    function test_BurnRateOracleNotSet() public {
        vm.startPrank(owner);
        TapSOLToken newToken = new TapSOLToken(owner, minter);
        vm.stopPrank();

        vm.startPrank(minter);
        newToken.mint(minter, 1000 * 10 ** 18);
        vm.expectRevert();
        newToken.burn(100 * 10 ** 18);
        vm.stopPrank();
    }

    function test_SetRateOracle() public {
        address newOracle = address(0x5);

        vm.startPrank(owner);
        tapSOLToken.setRateOracle(newOracle);
        vm.stopPrank();

        assertEq(address(tapSOLToken.rateOracle()), newOracle);
    }

    function test_SetRateOracleOnlyOwner() public {
        address newOracle = address(0x5);

        vm.startPrank(user1);
        vm.expectRevert();
        tapSOLToken.setRateOracle(newOracle);
        vm.stopPrank();

        assertEq(address(tapSOLToken.rateOracle()), address(tapSOLRate));
    }

    function test_SetMinter() public {
        address newMinter = address(0x5);

        vm.startPrank(owner);
        tapSOLToken.setMinter(newMinter);
        vm.stopPrank();

        assertEq(tapSOLToken.minter(), newMinter);
    }

    function test_SetMinterOnlyOwner() public {
        address newMinter = address(0x5);

        vm.startPrank(user1);
        vm.expectRevert();
        tapSOLToken.setMinter(newMinter);
        vm.stopPrank();

        assertEq(tapSOLToken.minter(), minter);
    }

    function test_GetExchangeRate() public view {
        assertEq(tapSOLToken.getExchangeRate(), tapSOLRate.getRate());
    }

    function test_GetSolValue() public view {
        uint256 tapSOLAmount = 1000 * 10 ** 18;
        uint256 expectedSolValue = (tapSOLAmount * tapSOLRate.getRate()) / (10 ** 18);

        assertEq(tapSOLToken.getSolValue(tapSOLAmount), expectedSolValue);
    }
}
