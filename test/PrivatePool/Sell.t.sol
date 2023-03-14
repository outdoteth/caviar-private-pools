// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract SellTest is Fixture {
    event Sell(uint256[] tokenIds, uint256[] tokenWeights, uint256 outputAmount, uint256 feeAmount);

    PrivatePool public privatePool;

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100e18;
    uint128 virtualNftReserves = 5e18;
    uint56 changeFee = 123908;
    uint16 feeRate = 0;
    bytes32 merkleRoot = bytes32(0);
    address owner = address(this);

    IStolenNftOracle.Message[] stolenNftProofs;
    uint256[] tokenIds;
    uint256[] tokenWeights;

    PrivatePool.MerkleMultiProof proofs;

    function setUp() public {
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, true
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
        (uint256 netOutputAmount, uint256 feeAmount,) = privatePool.sellQuote(tokenIds.length * 1e18);

        // act
        (uint256 returnedNetOutputAmount, uint256 returnedFeeAmount,) =
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
        (uint256 netOutputAmount, uint256 feeAmount,) = privatePool.sellQuote(tokenIds.length * 1e18);

        // act
        vm.expectEmit(true, true, true, true);
        emit Sell(tokenIds, tokenWeights, netOutputAmount, feeAmount);
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);
    }

    function test_TransfersBaseTokenToCaller() public {
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
            true
        );

        deal(address(shibaInu), address(privatePool), virtualBaseTokenReserves);
        milady.setApprovalForAll(address(privatePool), true);

        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netOutputAmount,,) = privatePool.sellQuote(tokenIds.length * 1e18);

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
        (uint256 netOutputAmount,,) = privatePool.sellQuote(tokenIds.length * 1e18);
        uint256 balanceBefore = address(this).balance;

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(address(this).balance - balanceBefore, netOutputAmount, "Should have transferred eth to caller");
    }

    function test_TransfersProtocolFee() public {
        // arrange
        factory.setProtocolFeeRate(1000); // 1%
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        (uint256 netOutputAmount,, uint256 protocolFeeAmount) = privatePool.sellQuote(tokenIds.length * 1e18);

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(address(factory).balance, protocolFeeAmount, "Should have transferred protocol fee to factory");
        assertGt(address(factory).balance, 0, "Should have transferred protocol fee to factory");
    }

    function test_TransfersBaseTokenProtocolFee() public {
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
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        milady.setApprovalForAll(address(privatePool), true);
        (uint256 netOutputAmount,, uint256 protocolFeeAmount) = privatePool.sellQuote(tokenIds.length * 1e18);
        deal(address(shibaInu), address(privatePool), netOutputAmount + protocolFeeAmount);

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(
            shibaInu.balanceOf(address(factory)), protocolFeeAmount, "Should have transferred protocol fee to factory"
        );
        assertGt(shibaInu.balanceOf(address(factory)), 0, "Should have transferred protocol fee to factory");
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
        (uint256 netOutputAmount, uint256 feeAmount,) = privatePool.sellQuote(tokenIds.length * 1e18);

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

    function test_PaysRoyaltiesIfRoyaltiesAreSet() public {
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
        (uint256 netOutputAmount,,) = privatePool.sellQuote(tokenIds.length * 1e18);
        uint256 royaltyFee = netOutputAmount * royaltyFeeRate / 1e18;
        netOutputAmount = netOutputAmount - royaltyFee;

        // act
        (uint256 returnedNetOutputAmount,,) = privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(royaltyRecipient.balance, royaltyFee, "Should have paid royalty fee");
        assertEq(returnedNetOutputAmount, netOutputAmount, "Should have returned net output amount");
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
            true
        );

        deal(address(privatePool), virtualBaseTokenReserves);
        milady.setApprovalForAll(address(privatePool), true);

        tokenIds.push(1);
        tokenWeights.push(1.1e18);
        tokenIds.push(3);
        tokenWeights.push(3.1e18);
        proofs = generateMerkleProofs(tokenIds, tokenWeights);
        (uint256 netOutputAmount,,) = privatePool.sellQuote(1.1e18 + 3.1e18);
        uint256 balanceBefore = address(this).balance;

        // act
        privatePool.sell(tokenIds, tokenWeights, proofs, stolenNftProofs);

        // assert
        assertEq(address(this).balance - balanceBefore, netOutputAmount, "Should have sent netOutputAmount to caller");
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
            true
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
