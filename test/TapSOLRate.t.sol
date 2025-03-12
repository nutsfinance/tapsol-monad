// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "wormhole-solidity-sdk/QueryResponse.sol";
import "../src/TapSOLRate.sol";
import {WormholeMock} from "wormhole-solidity-sdk/testing/helpers/WormholeMock.sol";

contract TapSOLRateTest is Test {
    using BytesParsing for bytes;

    event RateUpdated(
        uint64 indexed epoch,
        uint64 solanaSlotNumber,
        uint64 solanaBlockTime,
        uint64 totalTapSOLSupply,
        uint64 totalSOLValue,
        uint256 calculatedRate
    );

    TapSOLRate public tapSOLRate;

    uint256 constant MOCK_GUARDIAN_PRIVATE_KEY =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;
    uint8 sigGuardianIndex = 0;

    uint256 THIRTY_MINUTES = 60 * 30;
    uint256 THIRTY_DAYS = 60 * 60 * 24 * 30;
    bytes32 mockTapSOLPoolAccount =
        0x048a3e08c3b495be17f45427d89bec5b80c7e2695c1864d76743db39bed346d6;

    bytes mockDevnetResponse =
        hex"010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000073010000002a01000104000000660000000966696e616c697a656400000000000000000000000000000000000000000000011a02048a3e08c3b495be17f45427d89bec5b80c7e2695c1864d76743db39bed346d606a7d51718c774c928566398691d5eb68b5eb8a39b4b6d5c73555b210000000001000104000001dd000000000e8a333900060fbc482645c089cb4c158a7c669dfe20bef457ae808d671dc9a32f28cbc4b1f0ad3d406ea9380200000000004e7b9000000000000000000006814ed4caf68a174672fdac86031a63e84ea15efa1d44b72293f6dbdb0016500000011a01451e3dd50d3b7b8536045c2b7ac2ec259473ebc25ae3bcbe1fbeb17d52fbc7be0d095d453d5883bfeeb42269657a79abd0ed08bb66f986591ce4f00f950bd5c85a1fcd5de2beec843fe794ddc95faf466d40451c9faa569e7822d92c7e6ae13afd23e07509baddedfdb516a90b9197bb504743255d0e37c5ff5dce8a241eedc4319ea768fedf644c8aae9b8e2188add06bc550fbf716c822b9ce63c7783d952e1ffcd141e9832caf10ad917495ca0f271b5b293cd47027ea737007ed40eb39a0bd09e6a3feecf99032e1c1df6b9722dcb3634e7b8e3440936bc34b0cc1c8eb521f06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9c2dba43ab1ac1800eb5e0a9753bf16003402000000000000000000000011d78000000000000001690006a7d5171875f729c73d93408f216120067ed88c76e08c287fc1946000000000000000283c338a0e000000002af7af65000000003402000000000000350200000000000021cdb16500000000";
    uint8 mockDevnetSigV = 0x1c;
    bytes32 mockDevnetSigR =
        0x866bcea602aee0d95ab31dfff64c14382d2df83b2ff3a343a4167919b7e8dd90;
    bytes32 mockDevnetSigS =
        0x6065842f565b72d99a4b3519ba9acb78992b7e1222d7dee8ccddce97176e701e;
    uint64 mockSlot = 243_938_105;
    uint64 mockBlockTime = 1_706_151_199_000_000;
    uint64 mockEpoch = 564;
    uint64 mockTotalTapSOLSupply = 6_402_815_224_864_491;
    uint64 mockTotalSOLValue = 6_945_276_634_127_298;
    uint256 mockRate = 1_084_722_327_634_292_716;

    function setUp() public {
        vm.warp(mockBlockTime / 1_000_000);
        WormholeMock wormholeMock = new WormholeMock();
        tapSOLRate = new TapSOLRate(
            address(wormholeMock), mockTapSOLPoolAccount, THIRTY_MINUTES, THIRTY_DAYS
        );
    }

    function test_reverse_involutive(uint64 i) public view {
        assertEq(tapSOLRate.reverse(tapSOLRate.reverse(i)), i);
    }

    function test_reverse() public view {
        assertEq(tapSOLRate.reverse(0x0123456789ABCDEF), 0xEFCDAB8967452301);
    }

    function getSignature(bytes memory response)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 responseDigest = tapSOLRate.getResponseDigest(response);
        (v, r, s) = vm.sign(MOCK_GUARDIAN_PRIVATE_KEY, responseDigest);
    }

    function test_getSignature() public view {
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = getSignature(mockDevnetResponse);
        assertEq(sigV, mockDevnetSigV);
        assertEq(sigR, mockDevnetSigR);
        assertEq(sigS, mockDevnetSigS);
    }

    function test_valid_query() public {
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = getSignature(mockDevnetResponse);
        IWormhole.Signature[] memory signatures = new IWormhole.Signature[](1);
        signatures[0] = IWormhole.Signature({
            r: sigR,
            s: sigS,
            v: sigV,
            guardianIndex: sigGuardianIndex
        });

        tapSOLRate.updatePool(mockDevnetResponse, signatures);

        assertEq(
            tapSOLRate.lastUpdateSolanaSlotNumber(),
            mockSlot,
            "Slot number not updated correctly"
        );
        assertEq(
            tapSOLRate.lastUpdateSolanaBlockTime(),
            mockBlockTime,
            "Block time not updated correctly"
        );

        emit log_named_uint("Expected Total tapSOL Supply", mockTotalTapSOLSupply);
        emit log_named_uint("Actual Total tapSOL Supply", tapSOLRate.totalTapSOLSupply());
        assert(tapSOLRate.totalTapSOLSupply() > 0);

        emit log_named_uint("Expected Total SOL Value", mockTotalSOLValue);
        emit log_named_uint("Actual Total SOL Value", tapSOLRate.totalSOLValue());
        assert(tapSOLRate.totalSOLValue() > 0);

        uint256 actualRate = tapSOLRate.getRate();
        emit log_named_uint("Expected Rate (mock)", mockRate);
        emit log_named_uint("Actual Rate (contract)", actualRate);

        assert(actualRate > 0);

        if (actualRate > mockRate) {
            emit log_named_uint("Rate difference", actualRate - mockRate);
        } else {
            emit log_named_uint("Rate difference", mockRate - actualRate);
        }
    }

    function test_update_timestamp_underflow() public {
        vm.warp(1);
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = getSignature(mockDevnetResponse);
        IWormhole.Signature[] memory signatures = new IWormhole.Signature[](1);
        signatures[0] = IWormhole.Signature({
            r: sigR,
            s: sigS,
            v: sigV,
            guardianIndex: sigGuardianIndex
        });
        tapSOLRate.updatePool(mockDevnetResponse, signatures);
    }

    function test_rate_timestamp_underflow() public {
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = getSignature(mockDevnetResponse);
        IWormhole.Signature[] memory signatures = new IWormhole.Signature[](1);
        signatures[0] = IWormhole.Signature({
            r: sigR,
            s: sigS,
            v: sigV,
            guardianIndex: sigGuardianIndex
        });
        tapSOLRate.updatePool(mockDevnetResponse, signatures);
        vm.warp(1);
        tapSOLRate.getRate();
    }

    function test_max_timestamps() public {
        vm.warp(type(uint256).max);
        WormholeMock wormholeMock = new WormholeMock();
        TapSOLRate _tapSOLRate = new TapSOLRate(
            address(wormholeMock),
            mockTapSOLPoolAccount,
            type(uint256).max,
            type(uint256).max
        );
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = getSignature(mockDevnetResponse);
        IWormhole.Signature[] memory signatures = new IWormhole.Signature[](1);
        signatures[0] = IWormhole.Signature({
            r: sigR,
            s: sigS,
            v: sigV,
            guardianIndex: sigGuardianIndex
        });
        _tapSOLRate.updatePool(mockDevnetResponse, signatures);
        _tapSOLRate.getRate();
    }

    function test_calculateRate() public {
        assertEq(tapSOLRate.RATE_SCALE(), 18);
        assertEq(
            tapSOLRate.calculateRate(mockTotalSOLValue, mockTotalTapSOLSupply), mockRate
        );
        assertEq(tapSOLRate.calculateRate(1, 1), 1 * 10 ** tapSOLRate.RATE_SCALE());
        assertEq(tapSOLRate.calculateRate(2, 1), 2 * 10 ** tapSOLRate.RATE_SCALE());
        assertEq(tapSOLRate.calculateRate(1, 2), 5 * 10 ** (tapSOLRate.RATE_SCALE() - 1));
        assertEq(
            tapSOLRate.calculateRate(type(uint64).max, type(uint64).max),
            1 * 10 ** tapSOLRate.RATE_SCALE()
        );
        assertEq(tapSOLRate.calculateRate(0, 1), 0);
        vm.expectRevert();
        tapSOLRate.calculateRate(0, 0);
        vm.expectRevert();
        tapSOLRate.calculateRate(type(uint256).max, type(uint64).max);
    }
}
