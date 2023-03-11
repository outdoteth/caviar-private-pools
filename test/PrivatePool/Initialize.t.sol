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
        uint16 feeRate,
        bytes32 merkleRoot,
        address stolenNftOracle,
        bool payRoyalties
    );

    PrivatePool public privatePool;

    address baseToken = address(0x123);
    address nft = address(0x456);
    uint128 virtualBaseTokenReserves = 100;
    uint128 virtualNftReserves = 200;
    uint16 feeRate = 300;
    bytes32 merkleRoot = bytes32(abi.encode(0xaaa));
    address owner = address(0xdef);

    function setUp() public {
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry));
    }

    function test_EmitsInitializeEvent() public {
        // act
        vm.expectEmit(true, true, true, true);
        emit Initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            true
        );
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            true
        );
    }

    function test_SetsInitializedToTrue() public {
        // act
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            false
        );

        // assert
        assertTrue(privatePool.initialized(), "Should have marked initialized as true");
    }

    function test_InitializesStateVariables() public {
        // act
        testFuzz_InitializesStateVariables(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            false
        );
    }

    function test_RevertIf_AlreadyInitialized() public {
        // arrange
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            false
        );

        // act
        vm.expectRevert(PrivatePool.AlreadyInitialized.selector);
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            false
        );
    }

    function testFuzz_InitializesStateVariables(
        address _baseToken,
        address _nft,
        uint128 _virtualBaseTokenReserves,
        uint128 _virtualNftReserves,
        uint16 _feeRate,
        bytes32 _merkleRoot,
        address _stolenNftOracle,
        bool _payRoyalties
    ) public {
        // arrange
        _feeRate = uint16(bound(_feeRate, 0, 5_000));

        // act
        privatePool.initialize(
            _baseToken,
            _nft,
            _virtualBaseTokenReserves,
            _virtualNftReserves,
            _feeRate,
            _merkleRoot,
            _stolenNftOracle,
            _payRoyalties
        );

        // assert
        assertEq(privatePool.baseToken(), _baseToken);
        assertEq(privatePool.nft(), _nft);
        assertEq(privatePool.virtualBaseTokenReserves(), _virtualBaseTokenReserves);
        assertEq(privatePool.virtualNftReserves(), _virtualNftReserves);
        assertEq(privatePool.feeRate(), _feeRate);
        assertEq(privatePool.merkleRoot(), _merkleRoot);
        assertEq(privatePool.stolenNftOracle(), _stolenNftOracle);
        assertEq(privatePool.factory(), address(factory));
        assertEq(privatePool.payRoyalties(), _payRoyalties);
    }
}
