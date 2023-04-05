// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract BuyTest is Fixture {
    event Buy(
        uint256[] tokenIds,
        uint256[] tokenWeights,
        uint256 inputAmount,
        uint256 feeAmount,
        uint256 protocolFeeAmount,
        uint256 royaltyFeeAmount
    );

    PrivatePool public privatePool;

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100e18;
    uint128 virtualNftReserves = 5e18;
    uint16 feeRate = 0;
    uint56 changeFee = 0;
    bytes32 merkleRoot = bytes32(0);
    address owner = address(this);

    uint256[] tokenIds;
    uint256[] tokenWeights;
    PrivatePool.MerkleMultiProof proofs;

    function setUp() public {
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, false
        );

        for (uint256 i = 0; i < 5; i++) {
            milady.mint(address(privatePool), i);
        }

        milady.mint(address(this), 100);
    }

    function test_ReturnsNetInputAmount() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        (uint256 returnedNetInputAmount,,) = privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(returnedNetInputAmount, netInputAmount, "Should have returned netInputAmount");
    }

    function test_EmitsBuyEvent() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        (uint256 netInputAmount, uint256 feeAmount, uint256 protocolFeeAmount) =
            privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        vm.expectEmit(true, true, true, true);
        emit Buy(tokenIds, tokenWeights, netInputAmount, feeAmount, protocolFeeAmount, 0);
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);
    }

    function test_RefundsExcessEth() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        (uint256 netInputAmount,,) = privatePool.buyQuote(tokenIds.length * 1e18);
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

    function test_PaysProtocolFee() public {
        // arrange
        factory.setProtocolFeeRate(1_000); // 1%
        tokenIds.push(1);
        tokenIds.push(2);
        (uint256 netInputAmount,, uint256 protocolFeeAmount) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(address(factory).balance, protocolFeeAmount, "Should have paid protocol fee");
        assertGt(protocolFeeAmount, 0, "Should have paid protocol fee");
    }

    function test_PaysProtocolFeeWithBaseToken() public {
        // arrange
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false
        );
        factory.setProtocolFeeRate(1000); // 1%

        for (uint256 i = 10; i < 13; i++) {
            tokenIds.push(i);
            milady.mint(address(privatePool), i);
        }

        (uint256 netInputAmount,, uint256 protocolFeeAmount) = privatePool.buyQuote(tokenIds.length * 1e18);
        deal(address(shibaInu), address(this), netInputAmount);
        shibaInu.approve(address(privatePool), netInputAmount);

        // act
        privatePool.buy(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(shibaInu.balanceOf(address(factory)), protocolFeeAmount, "Should have paid protocol fee");
        assertGt(protocolFeeAmount, 0, "Should have paid protocol fee");
    }

    function test_TransfersNftsToCaller() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(milady.balanceOf(address(this)), tokenIds.length, "Should have incremented callers NFT balance");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(this), "Should have transferred NFTs to caller");
        }
    }

    function test_PaysRoyaltiesIfRoyaltyFeeIsSet() public {
        // arrange
        uint256 royaltyFeeRate = 0.1e18; // 10%
        address royaltyRecipient = address(0xbeefbeef);
        milady.setRoyaltyInfo(royaltyFeeRate, royaltyRecipient);
        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ERC721.ownerOf.selector, address(privatePool)),
            abi.encode(address(this))
        );
        privatePool.setPayRoyalties(true);
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netInputAmount,,) = privatePool.buyQuote(tokenIds.length * 1e18);
        uint256 royaltyFee = netInputAmount * royaltyFeeRate / 1e18;
        netInputAmount = netInputAmount + royaltyFee;

        // act
        (uint256 returnedNetInputAmount,,) = privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(royaltyRecipient.balance, royaltyFee, "Should have paid royalties");
        assertEq(returnedNetInputAmount, netInputAmount, "Should have returned net input amount");
    }

    function test_TransfersBaseTokensToPair() public {
        // arrange
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false
        );

        for (uint256 i = 10; i < 13; i++) {
            tokenIds.push(i);
            milady.mint(address(privatePool), i);
        }

        (uint256 netInputAmount,,) = privatePool.buyQuote(tokenIds.length * 1e18);
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
        (uint256 netInputAmount,,) = privatePool.buyQuote(tokenIds.length * 1e18);
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
        (uint256 netInputAmount,,) = privatePool.buyQuote(tokenIds.length * 1e18);

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.buy{value: netInputAmount - 1}(tokenIds, tokenWeights, proofs);
    }

    function test_RevertIf_CallerSentEthAndBaseTokenIsNotSetAsEth() public {
        // arrange
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false
        );

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.buy{value: 100}(tokenIds, tokenWeights, proofs);
    }

    function test_SumsWeightsIfMerkleRootIsSet() public {
        // arrange
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            generateMerkleRoot(),
            true,
            false
        );

        milady.mint(address(privatePool), 6);
        tokenIds.push(6);
        tokenWeights.push(2.7e18);
        proofs = generateMerkleProofs(tokenIds, tokenWeights);
        (uint256 netInputAmount,,) = privatePool.buyQuote(2.7e18);

        // act
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);

        // assert
        assertEq(address(privatePool).balance, netInputAmount, "Should sent netInputAmount to pool");
    }

    function test_RevertIf_InvalidMerkleProof() public {
        // arrange
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            generateMerkleRoot(),
            true,
            false
        );

        tokenIds.push(6);
        tokenWeights.push(2.7e18);
        proofs = generateMerkleProofs(tokenIds, tokenWeights);
        tokenWeights[0] = 2.11e18; // set to wrong weight
        (uint256 netInputAmount,,) = privatePool.buyQuote(2.7e18);

        // act
        vm.expectRevert(PrivatePool.InvalidMerkleProof.selector);
        privatePool.buy{value: netInputAmount}(tokenIds, tokenWeights, proofs);
    }
}
