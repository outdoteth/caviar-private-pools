// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract InitializeTest is Fixture {
    event Initialize(
        address indexed baseToken,
        address indexed nft,
        uint128 virtualBaseTokenReserves,
        uint128 virtualNftReserves,
        uint56 changeFee,
        uint16 feeRate,
        bytes32 merkleRoot,
        bool useStolenNftOracle,
        bool payRoyalties
    );

    PrivatePool public privatePool;

    address baseToken = address(0x123);
    address nft = address(0x456);
    uint128 virtualBaseTokenReserves = 100;
    uint128 virtualNftReserves = 200;
    uint16 feeRate = 300;
    uint56 changeFee = 10029;
    bytes32 merkleRoot = bytes32(abi.encode(0xaaa));
    address owner = address(0xdef);

    function setUp() public {
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
    }

    function test_EmitsInitializeEvent() public {
        // act
        vm.expectEmit(true, true, true, true);
        emit Initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, true
        );
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, true
        );
    }

    function test_SetsInitializedToTrue() public {
        // act
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, false
        );

        // assert
        assertTrue(privatePool.initialized(), "Should have marked initialized as true");
    }

    function test_InitializesStateVariables() public {
        // act
        testFuzz_InitializesStateVariables(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, false
        );
    }

    function test_RevertIf_AlreadyInitialized() public {
        // arrange
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, false
        );

        // act
        vm.expectRevert(PrivatePool.AlreadyInitialized.selector);
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, false
        );
    }

    function test_RevertIf_FeeRateIsTooHigh() public {
        // arrange
        feeRate = 5_001;

        // act
        vm.expectRevert(PrivatePool.FeeRateTooHigh.selector);
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, false
        );
    }

    function testFuzz_InitializesStateVariables(
        address _baseToken,
        address _nft,
        uint128 _virtualBaseTokenReserves,
        uint128 _virtualNftReserves,
        uint56 _changeFee,
        uint16 _feeRate,
        bytes32 _merkleRoot,
        bool _useStolenNftOracle,
        bool _payRoyalties
    ) public {
        if (_nft == address(factory)) return;

        // arrange
        _feeRate = uint16(bound(_feeRate, 0, 5_000));

        // act
        privatePool.initialize(
            _baseToken,
            _nft,
            _virtualBaseTokenReserves,
            _virtualNftReserves,
            _changeFee,
            _feeRate,
            _merkleRoot,
            _useStolenNftOracle,
            _payRoyalties
        );

        // assert
        assertEq(privatePool.baseToken(), _baseToken);
        assertEq(privatePool.nft(), _nft);
        assertEq(privatePool.virtualBaseTokenReserves(), _virtualBaseTokenReserves);
        assertEq(privatePool.virtualNftReserves(), _virtualNftReserves);
        assertEq(privatePool.changeFee(), _changeFee);
        assertEq(privatePool.feeRate(), _feeRate);
        assertEq(privatePool.merkleRoot(), _merkleRoot);
        assertEq(privatePool.useStolenNftOracle(), _useStolenNftOracle);
        assertEq(privatePool.factory(), address(factory));
        assertEq(privatePool.payRoyalties(), _payRoyalties);
    }
}
