// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract SettersTest is Fixture {
    event SetVirtualReserves(uint128 virtualBaseTokenReserves, uint128 virtualNftReserves);
    event SetMerkleRoot(bytes32 merkleRoot);
    event SetFeeRate(uint16 feeRate);
    event SetStolenNftOracle(address stolenNftOracle);
    event SetPayRoyalties(bool setPayRoyalties);

    PrivatePool public privatePool;

    address owner = address(this);

    function setUp() public {
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry));
        privatePool.initialize(
            address(shibaInu), address(0), 100, 200, 300, bytes32(abi.encode(0xaaa)), address(stolenNftOracle), true
        );

        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ERC721.ownerOf.selector, address(privatePool)),
            abi.encode(address(this))
        );
    }

    function test_setVirtualReserves_EmitsVirtualReservesEvent() public {
        // arrange
        uint128 virtualBaseTokenReserves = 100;
        uint128 virtualNftReserves = 200;

        // act
        vm.expectEmit(true, true, true, true);
        emit SetVirtualReserves(virtualBaseTokenReserves, virtualNftReserves);
        privatePool.setVirtualReserves(virtualBaseTokenReserves, virtualNftReserves);
    }

    function test_setVirtualReserves_SetsVirtualReserves() public {
        // arrange
        uint128 virtualBaseTokenReserves = 123456789;
        uint128 virtualNftReserves = 987654321;

        // act
        privatePool.setVirtualReserves(virtualBaseTokenReserves, virtualNftReserves);

        // assert
        assertEq(
            privatePool.virtualBaseTokenReserves(),
            virtualBaseTokenReserves,
            "Should have set virtual base token reserves"
        );
        assertEq(privatePool.virtualNftReserves(), virtualNftReserves, "Should have set virtual nft reserves");
    }

    function test_setVirtualReserves_RevertIf_NotOwner() public {
        // act
        vm.prank(address(0xbabe));
        vm.expectRevert(PrivatePool.Unauthorized.selector);
        privatePool.setVirtualReserves(100, 200);
    }

    function test_setMerkleRoot_EmitsMerkleRootEvent() public {
        // arrange
        bytes32 merkleRoot = bytes32(abi.encode(0xcafeBABE));

        // act
        vm.expectEmit(true, true, true, true);
        emit SetMerkleRoot(merkleRoot);
        privatePool.setMerkleRoot(merkleRoot);
    }

    function test_setMerkleRoot_SetsMerkleRoot() public {
        // arrange
        bytes32 merkleRoot = bytes32(abi.encode(0xcafeBABE));

        // act
        privatePool.setMerkleRoot(merkleRoot);

        // assert
        assertEq(privatePool.merkleRoot(), merkleRoot, "Should have set merkle root");
    }

    function test_setFeeRate_EmitsFeeRateEvent() public {
        // arrange
        uint16 feeRate = 4_000;

        // act
        vm.expectEmit(true, true, true, true);
        emit SetFeeRate(feeRate);
        privatePool.setFeeRate(feeRate);
    }

    function test_setFeeRate_setsFeeRate() public {
        // arrange
        uint16 feeRate = 4_000;

        // act
        privatePool.setFeeRate(feeRate);

        // assert
        assertEq(privatePool.feeRate(), feeRate, "Should have set fee rate");
    }

    function test_setFeeRate_RevertIf_NotOwner() public {
        // act
        vm.prank(address(0xbabe));
        vm.expectRevert(PrivatePool.Unauthorized.selector);
        privatePool.setFeeRate(4_000);
    }

    function test_setFeeRate_RevertIf_FeeRateTooHigh() public {
        // act
        vm.expectRevert(PrivatePool.FeeRateTooHigh.selector);
        privatePool.setFeeRate(5_555);
    }

    function test_setStolenNftOracle_EmitsStolenNftOracleEvent() public {
        // arrange
        address stolenNftOracle = address(0xdeadbeef);

        // act
        vm.expectEmit(true, true, true, true);
        emit SetStolenNftOracle(stolenNftOracle);
        privatePool.setStolenNftOracle(stolenNftOracle);
    }

    function test_setStolenNftOracle_SetsStolenNftOracle() public {
        // arrange
        address stolenNftOracle = address(0xdeadbeef);

        // act
        privatePool.setStolenNftOracle(stolenNftOracle);

        // assert
        assertEq(privatePool.stolenNftOracle(), stolenNftOracle, "Should have set stolen nft oracle");
    }

    function test_setStolenNftOracle_RevertIf_NotOwner() public {
        // act
        vm.prank(address(0xbabe));
        vm.expectRevert(PrivatePool.Unauthorized.selector);
        privatePool.setStolenNftOracle(address(0xdeadbeef));
    }

    function test_setPayRoyalties_EmitsSetPayRoyaltiesEvent() public {
        // arrange
        bool payRoyalties = false;

        // act
        vm.expectEmit(true, true, true, true);
        emit SetPayRoyalties(payRoyalties);
        privatePool.setPayRoyalties(payRoyalties);
    }

    function test_setPayRoyalties_SetsPayRoyalties() public {
        // arrange
        bool payRoyalties = true;

        // act
        privatePool.setPayRoyalties(payRoyalties);

        // assert
        assertEq(privatePool.payRoyalties(), payRoyalties, "Should have set pay royalties");
    }

    function test_setPayRoyalties_RevertIf_NotOwner() public {
        // act
        vm.prank(address(0xbabe));
        vm.expectRevert(PrivatePool.Unauthorized.selector);
        privatePool.setPayRoyalties(false);
    }
}
