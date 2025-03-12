// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TapSOLToken} from "../src/TapSOLToken.sol";
import {TapSOLRate} from "../src/TapSOLRate.sol";
import {TapSOLCollateralAdapter} from "../src/TapSOLCollateralAdapter.sol";
import {PythSOLPriceOracle} from "../src/PythSOLPriceOracle.sol";
import {WormholeMock} from "wormhole-solidity-sdk/testing/helpers/WormholeMock.sol";
import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";

/**
 * @title TapSOLIntegrationTest
 * @notice Integration tests simulating the complete user flow for NTT minting on Monad
 */
contract TapSOLIntegrationTest is Test {
    using BytesParsing for bytes;

    TapSOLToken public tapSOLToken;
    TapSOLRate public tapSOLRate;
    TapSOLCollateralAdapter public collateralAdapter;
    PythSOLPriceOracle public priceOracle;
    WormholeMock public wormholeMock;

    address deployer = address(0x1);
    address minter = address(0x2);
    address bridge = address(0x3);
    address user1 = address(0x4);
    address user2 = address(0x5);

    // Constants
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

    // Events
    event NTTMinted(address indexed user, uint256 amount, uint256 rate);
    event NTTBurned(address indexed user, uint256 amount, uint256 rate);
    event TokensBurned(address indexed account, uint256 amount, uint256 rate);

    function setUp() public {
        vm.warp(mockBlockTime / 1_000_000);
        vm.startPrank(deployer);

        wormholeMock = new WormholeMock();
        tapSOLRate = new TapSOLRate(
            address(wormholeMock), mockTapSOLPoolAccount, THIRTY_MINUTES, THIRTY_DAYS
        );

        bytes32 mockSolPriceFeedId = bytes32(uint256(1));
        uint256 mockMaxStaleness = 3600;
        priceOracle = new PythSOLPriceOracle(
            address(wormholeMock), mockSolPriceFeedId, mockMaxStaleness
        );

        tapSOLToken = new TapSOLToken(deployer, minter);

        tapSOLToken.setRateOracle(address(tapSOLRate));

        collateralAdapter = new TapSOLCollateralAdapter(
            address(tapSOLToken),
            address(priceOracle),
            12_500 // 125%
        );

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
        tapSOLRate.addAuthorizedUpdater(bridge);

        vm.stopPrank();
    }

    function test_CompleteUserFlow() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.startPrank(minter);
        emit log_string("Step 1: User mints tapSOL on Monad");

        tapSOLToken.mint(user1, mintAmount);
        assertEq(tapSOLToken.balanceOf(user1), mintAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 transferAmount = 300 * 10 ** 18;
        vm.startPrank(user1);

        emit log_string("Step 2: User transfers tapSOL to another user");
        tapSOLToken.transfer(user2, transferAmount);
        assertEq(tapSOLToken.balanceOf(user1), mintAmount - transferAmount);
        assertEq(tapSOLToken.balanceOf(user2), transferAmount);
        vm.stopPrank();

        emit log_string("Step 3: Check current exchange rate data");
        uint256 currentRate = tapSOLRate.getRate();
        emit log_named_uint("Current Rate", currentRate);
        assert(currentRate > 0);

        emit log_named_uint("Last Slot Number", tapSOLRate.lastUpdateSolanaSlotNumber());
        emit log_named_uint("Last Block Time", tapSOLRate.lastUpdateSolanaBlockTime());
        emit log_named_uint("Total tapSOL Supply", tapSOLRate.totalTapSOLSupply());
        emit log_named_uint("Total SOL Value", tapSOLRate.totalSOLValue());

        uint256 burnAmount = 200 * 10 ** 18;
        vm.startPrank(user1);
        emit log_string("Step 4: User approves minter to burn their tokens");
        tapSOLToken.approve(minter, burnAmount);
        assertEq(tapSOLToken.allowance(user1, minter), burnAmount);
        vm.stopPrank();

        vm.startPrank(minter);
        emit log_string("Step 5: Minter burns user tokens (bridging back to Solana)");
        tapSOLRate.getRate();
        tapSOLToken.burnFrom(user1, burnAmount);
        assertEq(tapSOLToken.balanceOf(user1), mintAmount - transferAmount - burnAmount);
        vm.stopPrank();

        // Expected balances
        uint256 user1ExpectedBalance = mintAmount - transferAmount - burnAmount;
        uint256 user2ExpectedBalance = transferAmount;
        uint256 totalExpectedSupply = user1ExpectedBalance + user2ExpectedBalance;

        // Verify final state
        assertEq(tapSOLToken.balanceOf(user1), user1ExpectedBalance);
        assertEq(tapSOLToken.balanceOf(user2), user2ExpectedBalance);
        assertEq(tapSOLToken.totalSupply(), totalExpectedSupply);
    }

    function test_CollateralAdapterBasics() public {
        uint256 testCollateralRatio = 12_000; // 120%
        vm.startPrank(deployer);
        collateralAdapter.setCollateralRatio(testCollateralRatio);
        vm.stopPrank();

        assertEq(
            collateralAdapter.collateralRatio(),
            testCollateralRatio,
            "Collateral ratio wasn't set correctly"
        );

        uint256 collateralAmount = 100 * 10 ** 18; // 100 tapSOL
        uint256 expectedMaxLoan = (collateralAmount * 10_000) / testCollateralRatio;

        emit log_named_uint("Collateral Amount (tapSOL)", collateralAmount / 10 ** 18);
        emit log_named_uint("Collateral Ratio", testCollateralRatio);
        emit log_named_uint("Expected Max Loan (normalized)", expectedMaxLoan / 10 ** 18);

        assert(expectedMaxLoan < collateralAmount);

        uint256 calculated = (expectedMaxLoan * testCollateralRatio) / 10_000;
        emit log_named_uint("Formula result", calculated);

        assert(calculated <= collateralAmount && collateralAmount - calculated <= 1);

        uint256 newCollateralRatio = 15_000; // 150%
        vm.startPrank(deployer);
        collateralAdapter.setCollateralRatio(newCollateralRatio);
        vm.stopPrank();

        uint256 newExpectedMaxLoan = (collateralAmount * 10_000) / newCollateralRatio;
        emit log_named_uint("New Collateral Ratio", newCollateralRatio);
        emit log_named_uint(
            "New Expected Max Loan (normalized)", newExpectedMaxLoan / 10 ** 18
        );

        assert(newExpectedMaxLoan < expectedMaxLoan);

        uint256 newCalculated = (newExpectedMaxLoan * newCollateralRatio) / 10_000;
        emit log_named_uint("New formula result", newCalculated);

        assert(newCalculated <= collateralAmount && collateralAmount - newCalculated <= 1);
    }

    function test_ErrorScenarios() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.startPrank(user1);
        emit log_string("Attempting unauthorized minting");
        vm.expectRevert();
        tapSOLToken.mint(user1, mintAmount);
        vm.stopPrank();

        vm.startPrank(minter);
        tapSOLToken.mint(user1, mintAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        emit log_string("Attempting unauthorized burning");
        vm.expectRevert();
        tapSOLToken.burn(100 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(minter);
        emit log_string("Attempting burn without approval");
        vm.expectRevert();
        tapSOLToken.burnFrom(user1, 100 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user1);
        emit log_string("Attempting transfer exceeding balance");
        vm.expectRevert();
        tapSOLToken.transfer(user2, mintAmount + 1);
        vm.stopPrank();
    }

    function test_MonadSpecificFeatures() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.startPrank(minter);
        tapSOLToken.mint(user1, mintAmount);
        tapSOLToken.mint(user2, mintAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        emit log_string("Delegating voting power");
        tapSOLToken.delegate(user2);

        uint256 user1VotingPower = tapSOLToken.getVotes(user1);
        uint256 user2VotingPower = tapSOLToken.getVotes(user2);

        emit log_named_uint("User1 voting power", user1VotingPower);
        emit log_named_uint("User2 voting power", user2VotingPower);

        tapSOLToken.transfer(user2, 100 * 10 ** 18);

        uint256 user1VotingPowerAfter = tapSOLToken.getVotes(user1);
        uint256 user2VotingPowerAfter = tapSOLToken.getVotes(user2);

        emit log_named_uint("User1 voting power after transfer", user1VotingPowerAfter);
        emit log_named_uint("User2 voting power after transfer", user2VotingPowerAfter);
        vm.stopPrank();
    }

    function test_PermitFunctionality() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        vm.startPrank(minter);
        tapSOLToken.mint(user1, mintAmount);
        vm.stopPrank();

        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        address spender = user2;
        uint256 value = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 days;

        vm.startPrank(minter);
        tapSOLToken.mint(owner, mintAmount);
        vm.stopPrank();

        bytes32 domainSeparator = tapSOLToken.DOMAIN_SEPARATOR();
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash, owner, spender, value, tapSOLToken.nonces(owner), deadline
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        emit log_string("Executing permit function");
        tapSOLToken.permit(owner, spender, value, deadline, v, r, s);

        assertEq(tapSOLToken.allowance(owner, spender), value);

        vm.startPrank(spender);
        tapSOLToken.transferFrom(owner, spender, value);
        assertEq(tapSOLToken.balanceOf(spender), value);
        vm.stopPrank();
    }
}
