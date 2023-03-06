// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract BuyTest is Fixture {
    event Buy(
        uint256[] indexed tokenIds, uint256[] indexed tokenWeights, uint256 indexed inputAmount, uint256 feeAmount
    );

    PrivatePool public privatePool;

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100e18;
    uint128 virtualNftReserves = 5e18;
    uint16 feeRate = 0;
    bytes32 merkleRoot = bytes32(0);
    address owner = address(this);

    uint256[] tokenIds;
    uint256[] tokenWeights;
    PrivatePool.MerkleMultiProof proofs;

    function setUp() public {
        privatePool = new PrivatePool();
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            owner
        );

        for (uint256 i = 0; i < 5; i++) {
            milady.mint(address(privatePool), i);
        }
    }

    function test_ReturnsNetInputAmount() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        (uint256 returnedNetInputAmount,) = privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(returnedNetInputAmount, netInputAmount, "Should have returned netInputAmount");
    }

    function test_EmitsBuyEvent() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount, uint256 feeAmount) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        vm.expectEmit(true, true, true, true);
        emit Buy(tokenIds, tokenWeights, netInputAmount, feeAmount);
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);
    }

    function test_RefundsExcessEth() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);
        uint256 surplus = 0.123e18;
        uint256 balanceBefore = address(this).balance;

        // act
        privatePool.buy{value: netInputAmount + surplus}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(
            balanceBefore - address(this).balance,
            netInputAmount,
            "Should have refunded anything surplus to netInputAmount"
        );
    }

    function test_TransfersNftsToCaller() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(milady.balanceOf(address(this)), tokenIds.length, "Should have incremented callers NFT balance");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(this), "Should have transferred NFTs to caller");
        }
    }

    function test_TransfersBaseTokensToPair() public {
        // arrange
        privatePool = new PrivatePool();
        privatePool.initialize(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            owner
        );

        for (uint256 i = 10; i < 13; i++) {
            tokenIds.push(i);
            milady.mint(address(privatePool), i);
        }

        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);
        deal(address(shibaInu), address(this), netInputAmount);
        shibaInu.approve(address(privatePool), netInputAmount);
        uint256 poolBalanceBefore = shibaInu.balanceOf(address(privatePool));
        uint256 callerBalanceBefore = shibaInu.balanceOf(address(this));

        // act
        privatePool.buy(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(
            shibaInu.balanceOf(address(privatePool)) - poolBalanceBefore,
            netInputAmount,
            "Should have transferred tokens to pool"
        );

        assertEq(
            callerBalanceBefore - shibaInu.balanceOf(address(this)),
            netInputAmount,
            "Should have transferred tokens from caller"
        );
    }

    function test_UpdatesVirtualReserves() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);
        uint256 virtualBaseTokenReservesBefore = privatePool.virtualBaseTokenReserves();
        uint256 virtualNftReservesBefore = privatePool.virtualNftReserves();

        // act
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(
            privatePool.virtualBaseTokenReserves(),
            virtualBaseTokenReservesBefore + netInputAmount,
            "Should have incremented virtualBaseTokenReserves"
        );

        assertEq(
            privatePool.virtualNftReserves(),
            virtualNftReservesBefore - tokenIds.length * 1e18,
            "Should have decremented virtualNftReserves"
        );
    }

    function test_RevertIf_CallerSentLessEthThanNetInputAmount() public {
        // arrange
        tokenIds.push(1);
        (uint256 netInputAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.buy{value: netInputAmount - 1}(tokenIds, tokenWeights, proofs);
    }

    function test_RevertIf_CallerSentEthAndBaseTokenIsNotSetAsEth() public {
        // arrange
        privatePool = new PrivatePool();
        privatePool.initialize(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            owner
        );

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.buy{value: 100}(tokenIds, tokenWeights, proofs);
    }

    function test_SumsWeightsIfMerkleRootIsSet() public {
        // arrange
        privatePool = new PrivatePool();
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            generateMerkleRoot(),
            address(stolenNftOracle),
            owner
        );

        milady.mint(address(privatePool), 6);
        tokenIds.push(6);
        tokenWeights.push(2.7e18);
        proofs = generateMerkleProofs(tokenIds, tokenWeights);
        (uint256 netInputAmount,) = privatePool.buyQuote(2.7e18);

        // act
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(address(privatePool).balance, netInputAmount, "Should sent netInputAmount to pool");
    }

    function test_RevertIf_InvalidMerkleProof() public {
        // arrange
        privatePool = new PrivatePool();
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            generateMerkleRoot(),
            address(stolenNftOracle),
            owner
        );

        tokenIds.push(6);
        tokenWeights.push(2.7e18);
        proofs = generateMerkleProofs(tokenIds, tokenWeights);
        tokenWeights[0] = 2.11e18; // set to wrong weight
        (uint256 netInputAmount,) = privatePool.buyQuote(2.7e18);

        // act
        vm.expectRevert(PrivatePool.InvalidMerkleProof.selector);
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);
    }
}
