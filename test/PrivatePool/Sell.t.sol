// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract SellTest is Fixture {
    event Sell(
        uint256[] indexed tokenIds, uint256[] indexed tokenWeights, uint256 indexed outputAmount, uint256 feeAmount
    );

    PrivatePool public privatePool;

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100e18;
    uint128 virtualNftReserves = 5e18;
    uint16 feeRate = 0;
    bytes32 merkleRoot = bytes32(0);
    address owner = address(this);

    IStolenNftOracle.Message[] stolenNftProofs;
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

        deal(address(privatePool), virtualBaseTokenReserves);

        for (uint256 i = 0; i < 5; i++) {
            milady.mint(address(this), i);
        }

        milady.setApprovalForAll(address(privatePool), true);
    }

    function test_ReturnsNetOutputAmountAndFeeAmount() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netOutputAmount, uint256 feeAmount) = privatePool.sellQuote(tokenIds.length * 1e18);

        // act
        (uint256 returnedNetOutputAmount, uint256 returnedFeeAmount) =
            privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(returnedNetOutputAmount, netOutputAmount, "Should have returned netOutputAmount");
        assertEq(returnedFeeAmount, feeAmount, "Should have returned feeAmount");
    }

    function test_EmitsSellEvent() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netOutputAmount, uint256 feeAmount) = privatePool.sellQuote(tokenIds.length * 1e18);

        // act
        vm.expectEmit(true, true, true, true);
        emit Sell(tokenIds, tokenWeights, netOutputAmount, feeAmount);
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);
    }

    function test_TransfersBaseTokenToCaller() public {
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

        deal(address(shibaInu), address(privatePool), virtualBaseTokenReserves);
        milady.setApprovalForAll(address(privatePool), true);

        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netOutputAmount,) = privatePool.sellQuote(tokenIds.length * 1e18);

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(shibaInu.balanceOf(address(this)), netOutputAmount, "Should have transferred baseToken to caller");
    }

    function test_TransfersEthToCaller() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netOutputAmount,) = privatePool.sellQuote(tokenIds.length * 1e18);
        uint256 balanceBefore = address(this).balance;

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(address(this).balance - balanceBefore, netOutputAmount, "Should have transferred eth to caller");
    }

    function test_TransfersNftsToPool() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(milady.balanceOf(address(privatePool)), tokenIds.length, "Should have incremented pool nft balance");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(privatePool), "Should have transferred nfts to pool");
        }
    }

    function test_ValidatesNftsAreNotStolen() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);

        // act
        vm.expectCall(
            address(stolenNftOracle),
            abi.encodeCall(stolenNftOracle.validateTokensAreNotStolen, (address(milady), tokenIds, stolenNftProofs))
        );
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);
    }

    function test_RevertIf_NftsAreMarkedAsStolen() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        stolenNftOracle.setStolenNft(address(milady), 2);

        // act
        vm.expectRevert(StolenNftOracle.StolenNft.selector);
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);
    }

    function test_UpdatesVirtualReserves() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netOutputAmount, uint256 feeAmount) = privatePool.sellQuote(tokenIds.length * 1e18);

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(
            privatePool.virtualBaseTokenReserves(),
            virtualBaseTokenReserves - (netOutputAmount - feeAmount),
            "Should have updated virtualBaseTokenReserves"
        );
        assertEq(
            privatePool.virtualNftReserves(),
            virtualNftReserves + tokenIds.length * 1e18,
            "Should have updated virtualNftReserves"
        );
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

        deal(address(privatePool), virtualBaseTokenReserves);
        milady.setApprovalForAll(address(privatePool), true);

        tokenIds.push(1);
        tokenWeights.push(1.1e18);
        tokenIds.push(3);
        tokenWeights.push(3.1e18);
        proofs = generateMerkleProofs(tokenIds, tokenWeights);
        (uint256 netOutputAmount,) = privatePool.sellQuote(1.1e18 + 3.1e18);
        uint256 balanceBefore = address(this).balance;

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(address(this).balance - balanceBefore, netOutputAmount, "Should have sent netOutputAmount to caller");
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

        deal(address(privatePool), virtualBaseTokenReserves);
        milady.setApprovalForAll(address(privatePool), true);

        tokenIds.push(1);
        tokenWeights.push(1.1e18);
        tokenIds.push(3);
        tokenWeights.push(3.1e18);
        proofs = generateMerkleProofs(tokenIds, tokenWeights);
        tokenWeights[0] = 1.2e18;

        // act
        vm.expectRevert(PrivatePool.InvalidMerkleProof.selector);
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);
    }
}
