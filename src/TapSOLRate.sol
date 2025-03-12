// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "wormhole-solidity-sdk/QueryResponse.sol";

error NotOwner(); // 0x30cd7471
error ZeroAddress(); // 0xd92e233d
error SlotNumberNotIncreasing(); // 0xc9417c08
error BlockTimeTooOld(); // 0x2b781d1d
error InvalidAccount(); // 0x6d187b28
error InvalidAccountOwner(); // 0x36b1fa3a
error InvalidCommitmentLevel(); // 0xffe74dc8
error InvalidDataSlice(); // 0xf1b1ecf1
error InvalidForeignChainID(); // 0x4efe96a9
error UnexpectedDataLength(); // 0x9546c78e
error UnexpectedEpochMismatch(); // 0x1e0cfb5e
error UnexpectedResultLength(); // 0x3a279ba1
error UnexpectedResultMismatch(); // 0x1dd329af

contract TapSOLRate is QueryResponse {
    using BytesParsing for bytes;

    uint8 public constant RATE_SCALE = 18;

    event RateUpdated(
        uint64 indexed epoch,
        uint64 solanaSlotNumber,
        uint64 solanaBlockTime,
        uint64 totalTapSOLSupply,
        uint64 totalSOLValue,
        uint256 calculatedRate
    );

    uint64 public totalTapSOLSupply;
    uint64 public totalSOLValue;
    uint64 public lastUpdateSolanaSlotNumber;
    uint64 public lastUpdateSolanaBlockTime;
    uint256 public calculatedRate;

    uint256 public immutable allowedUpdateStaleness;
    uint256 public immutable allowedRateStaleness;
    bytes32 public immutable tapSOLPoolAccount;

    address public owner;
    mapping(address => bool) public authorizedRateUpdaters;

    uint16 public constant SOLANA_CHAIN_ID = 1;
    bytes12 public constant SOLANA_COMMITMENT_LEVEL = "finalized";
    bytes32 public constant TAPIO_SOL_PROGRAM =
        0x06814ed4caf68a174672fdac86031a63e84ea15efa1d44b72293f6dbdb001650;
    bytes32 public constant SOLANA_SYSVAR_CLOCK =
        0x06a7d51718c774c928566398691d5eb68b5eb8a39b4b6d5c73555b2100000000;
    uint64 public constant EXPECTED_DATA_OFFSET = 0;
    uint64 public constant TAPIO_POOL_EXPECTED_DATA_LENGTH = 282;
    uint256 public constant TAPIO_POOL_FIRST_FIELD_BYTE_IDX = 258;
    uint64 public constant SYSVAR_CLOCK_EXPECTED_DATA_LENGTH = 40;
    uint256 public constant SYSVAR_CLOCK_FIRST_FIELD_BYTE_IDX = 16;

    constructor(
        address _wormhole,
        bytes32 _tapSOLPoolAccount,
        uint256 _allowedUpdateStaleness,
        uint256 _allowedRateStaleness
    )
        QueryResponse(_wormhole)
    {
        tapSOLPoolAccount = _tapSOLPoolAccount;
        allowedUpdateStaleness = _allowedUpdateStaleness;
        allowedRateStaleness = _allowedRateStaleness;
        owner = msg.sender;
        authorizedRateUpdaters[msg.sender] = true;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, NotOwner());
        _;
    }

    function setOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), ZeroAddress());
        owner = _newOwner;
    }

    function addAuthorizedUpdater(address _updater) external onlyOwner {
        require(_updater != address(0), ZeroAddress());
        authorizedRateUpdaters[_updater] = true;
    }

    function removeAuthorizedUpdater(address _updater) external onlyOwner {
        authorizedRateUpdaters[_updater] = false;
    }

    // @notice Fetches query response for tapSOL pool on Solana
    function updatePool(
        bytes memory response,
        IWormhole.Signature[] memory signatures
    )
        public
    {
        ParsedQueryResponse memory r = parseAndVerifyQueryResponse(response, signatures);
        if (r.responses.length != 1) revert UnexpectedResultLength();
        if (r.responses[0].chainId != SOLANA_CHAIN_ID) revert InvalidForeignChainID();
        SolanaAccountQueryResponse memory s =
            parseSolanaAccountQueryResponse(r.responses[0]);
        if (
            s.requestCommitment.length > 12
                || bytes12(s.requestCommitment) != SOLANA_COMMITMENT_LEVEL
        ) revert InvalidCommitmentLevel();
        if (
            s.requestDataSliceOffset != EXPECTED_DATA_OFFSET
                || s.requestDataSliceLength != TAPIO_POOL_EXPECTED_DATA_LENGTH
        ) revert InvalidDataSlice();
        if (s.results.length != 2) revert UnexpectedResultLength();
        if (s.results[0].account != tapSOLPoolAccount) revert InvalidAccount();
        if (s.results[0].owner != TAPIO_SOL_PROGRAM) revert InvalidAccountOwner();
        if (s.results[1].account != SOLANA_SYSVAR_CLOCK) revert InvalidAccount();
        require(s.slotNumber > lastUpdateSolanaSlotNumber, SlotNumberNotIncreasing());
        uint256 minTimestamp = allowedUpdateStaleness >= block.timestamp
            ? 0
            : block.timestamp - allowedUpdateStaleness;
        require(s.blockTime >= minTimestamp, BlockTimeTooOld());
        if (s.results[0].data.length != TAPIO_POOL_EXPECTED_DATA_LENGTH) {
            revert UnexpectedDataLength();
        }
        if (s.results[1].data.length != SYSVAR_CLOCK_EXPECTED_DATA_LENGTH) {
            revert UnexpectedDataLength();
        }
        uint64 _totalTapSOLSupplyLE;
        uint64 _totalSOLValueLE;
        uint64 _lastUpdateEpochLE;
        uint64 _clockEpochLE;
        uint256 offset = TAPIO_POOL_FIRST_FIELD_BYTE_IDX;
        (_totalTapSOLSupplyLE, offset) = s.results[0].data.asUint64Unchecked(offset);
        (_totalSOLValueLE, offset) = s.results[0].data.asUint64Unchecked(offset);
        (_lastUpdateEpochLE, offset) = s.results[0].data.asUint64Unchecked(offset);
        offset = SYSVAR_CLOCK_FIRST_FIELD_BYTE_IDX;
        (_clockEpochLE, offset) = s.results[1].data.asUint64Unchecked(offset);
        if (_lastUpdateEpochLE != _clockEpochLE) revert UnexpectedEpochMismatch();

        totalTapSOLSupply = reverse(_totalTapSOLSupplyLE);
        totalSOLValue = reverse(_totalSOLValueLE);

        lastUpdateSolanaSlotNumber = s.slotNumber;
        lastUpdateSolanaBlockTime = s.blockTime;

        calculatedRate = calculateRate(totalSOLValue, totalTapSOLSupply);

        emit RateUpdated(
            reverse(_clockEpochLE),
            s.slotNumber,
            s.blockTime,
            totalTapSOLSupply,
            totalSOLValue,
            calculatedRate
        );
    }

    function getRate() public view returns (uint256) {
        uint256 minTimestamp = allowedRateStaleness >= block.timestamp
            ? 0
            : block.timestamp - allowedRateStaleness;
        require(lastUpdateSolanaBlockTime >= minTimestamp, BlockTimeTooOld());
        return calculatedRate;
    }

    function reverse(uint64 input) public pure returns (uint64 v) {
        v = input;
        v = ((v & 0xFF00FF00FF00FF00) >> 8) | ((v & 0x00FF00FF00FF00FF) << 8);
        v = ((v & 0xFFFF0000FFFF0000) >> 16) | ((v & 0x0000FFFF0000FFFF) << 16);
        v = (v >> 32) | (v << 32);
    }

    function calculateRate(
        uint256 _totalSOLValue,
        uint256 _totalTapSOLSupply
    )
        public
        pure
        returns (uint256 v)
    {
        _totalSOLValue *= 10 ** RATE_SCALE;
        v = _totalSOLValue / _totalTapSOLSupply;
    }
}
