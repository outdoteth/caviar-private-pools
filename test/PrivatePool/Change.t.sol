// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract ChangeTest is Fixture {
    event Change(
        uint256[] inputTokenIds,
        uint256[] inputTokenWeights,
        uint256[] outputTokenIds,
        uint256[] outputTokenWeights,
        uint256 feeAmount,
        uint256 protocolFeeAmount
    );

    PrivatePool public privatePool;

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100e18;
    uint128 virtualNftReserves = 5e18;
    uint16 feeRate = 100;
    uint56 changeFee = 80000;
    bytes32 merkleRoot = bytes32(0);
    address owner = address(this);

    uint256[] inputTokenIds;
    uint256[] inputTokenWeights;
    PrivatePool.MerkleMultiProof inputProof;
    IStolenNftOracle.Message[] stolenNftProofs;

    uint256[] outputTokenIds;
    uint256[] outputTokenWeights;
    PrivatePool.MerkleMultiProof outputProof;

    function setUp() public {
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, changeFee, feeRate, merkleRoot, true, false
        );

        for (uint256 i = 0; i < 3; i++) {
            milady.mint(address(this), i);
        }

        for (uint256 i = 3; i < 6; i++) {
            milady.mint(address(privatePool), i);
        }

        milady.setApprovalForAll(address(privatePool), true);
    }

    function test_EmitsChangeEvent() public {
        // arrange
        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        outputTokenIds.push(3);
        outputTokenIds.push(4);
        outputTokenIds.push(5);
        (uint256 feeAmount, uint256 protocolFeeAmount) = privatePool.changeFeeQuote(inputTokenIds.length * 1e18);

        // act
        vm.expectEmit(true, true, true, true);
        emit Change(inputTokenIds, inputTokenWeights, outputTokenIds, outputTokenWeights, feeAmount, protocolFeeAmount);
        privatePool.change{value: feeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );
    }

    function test_TransfersOutputNftsToCaller() public {
        // arrange
        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        outputTokenIds.push(3);
        outputTokenIds.push(4);
        outputTokenIds.push(5);
        (uint256 feeAmount,) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);

        // act
        privatePool.change{value: feeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );

        // assert
        for (uint256 i = 0; i < outputTokenIds.length; i++) {
            assertEq(milady.ownerOf(outputTokenIds[i]), address(this));
        }
    }

    function test_TransfersInputNftsToPool() public {
        // arrange
        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        outputTokenIds.push(3);
        outputTokenIds.push(4);
        outputTokenIds.push(5);
        (uint256 feeAmount,) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);

        // act
        privatePool.change{value: feeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );

        // assert
        for (uint256 i = 0; i < inputTokenIds.length; i++) {
            assertEq(milady.ownerOf(inputTokenIds[i]), address(privatePool));
        }
    }

    function test_TransfersProtocolFeeToFactory() public {
        // arrange
        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        outputTokenIds.push(3);
        outputTokenIds.push(4);
        outputTokenIds.push(5);
        factory.setProtocolFeeRate(1000); // 1%
        (uint256 feeAmount, uint256 protocolFeeAmount) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);

        // act
        privatePool.change{value: feeAmount + protocolFeeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );

        // assert
        assertEq(address(factory).balance, protocolFeeAmount, "Should have transferred protocol fee to factory");
        assertGt(address(factory).balance, 0, "Should have transferred protocol fee to factory");
    }

    function test_TransfersBaseTokenProtocolFeeToFactory() public {
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

        milady.setApprovalForAll(address(privatePool), true);
        shibaInu.approve(address(privatePool), type(uint256).max);

        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        milady.mint(address(privatePool), 10);
        milady.mint(address(privatePool), 11);
        milady.mint(address(privatePool), 12);
        outputTokenIds.push(10);
        outputTokenIds.push(11);
        outputTokenIds.push(12);
        factory.setProtocolFeeRate(1000); // 1%
        (uint256 feeAmount, uint256 protocolFeeAmount) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);
        deal(address(shibaInu), address(this), feeAmount + protocolFeeAmount);

        // act
        privatePool.change(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );

        // assert
        assertEq(
            shibaInu.balanceOf(address(factory)), protocolFeeAmount, "Should have transferred protocol fee to factory"
        );
        assertGt(shibaInu.balanceOf(address(factory)), 0, "Should have transferred protocol fee to factory");
    }

    function test_RefundsExcessEth() public {
        // arrange
        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        outputTokenIds.push(3);
        outputTokenIds.push(4);
        outputTokenIds.push(5);
        (uint256 feeAmount,) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);
        uint256 balanceBefore = address(this).balance;

        // act
        privatePool.change{value: feeAmount + 1e18}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );

        // assert
        assertEq(balanceBefore - address(this).balance, feeAmount, "Should have refunded excess eth");
        assertEq(address(privatePool).balance, feeAmount, "Should have only transferred fee amount to pool");
    }

    function test_TransfersBaseTokensIfBaseTokenIsNotEth() public {
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

        milady.setApprovalForAll(address(privatePool), true);
        shibaInu.approve(address(privatePool), type(uint256).max);

        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        milady.mint(address(privatePool), 10);
        milady.mint(address(privatePool), 11);
        milady.mint(address(privatePool), 12);
        outputTokenIds.push(10);
        outputTokenIds.push(11);
        outputTokenIds.push(12);
        (uint256 feeAmount,) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);
        deal(address(shibaInu), address(this), feeAmount);
        uint256 balanceBefore = shibaInu.balanceOf(address(this));

        // act
        privatePool.change(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );

        // assert
        assertEq(shibaInu.balanceOf(address(privatePool)), feeAmount, "Should have transferred base tokens to pool");
        assertEq(
            balanceBefore - shibaInu.balanceOf(address(this)),
            feeAmount,
            "Should have transferred base tokens from caller"
        );
    }

    function test_RevertIf_BaseTokenIsNotEthAndValueIsGreaterThanZero() public {
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
        privatePool.change{value: 1e18}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );
    }

    function test_RevertIf_BaseTokenIsEthAndValueIsLessThanFeeAmount() public {
        // arrange
        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        outputTokenIds.push(3);
        outputTokenIds.push(4);
        outputTokenIds.push(5);
        (uint256 feeAmount,) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.change{value: feeAmount - 1}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );
    }

    function test_RevertIf_InputWeightsAreLessThanOutputWeights() public {
        // arrange
        inputTokenIds.push(0);
        inputTokenIds.push(1);

        outputTokenIds.push(3);
        outputTokenIds.push(4);
        outputTokenIds.push(5);
        (uint256 feeAmount,) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);

        // act
        vm.expectRevert(PrivatePool.InsufficientInputWeight.selector);
        privatePool.change{value: feeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );
    }

    function test_EmitChangeEventIfMerkleRootAndWeightsAreSet() public {
        // arrange
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            address(0),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            generateMerkleRoot(),
            true,
            false
        );

        milady.setApprovalForAll(address(privatePool), true);

        inputTokenIds.push(1);
        inputTokenIds.push(2);
        inputTokenWeights.push(1.1e18);
        inputTokenWeights.push(1.15e18);

        milady.mint(address(privatePool), 8);
        outputTokenIds.push(8);
        outputTokenWeights.push(1.11e18);

        inputProof = generateMerkleProofs(inputTokenIds, inputTokenWeights);
        outputProof = generateMerkleProofs(outputTokenIds, outputTokenWeights);

        (uint256 feeAmount, uint256 protocolFeeAmount) = privatePool.changeFeeQuote(1.1e18 + 1.15e18);

        // act
        vm.expectEmit(true, true, true, true);
        emit Change(inputTokenIds, inputTokenWeights, outputTokenIds, outputTokenWeights, feeAmount, protocolFeeAmount);
        privatePool.change{value: feeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );
    }

    function test_RevertIf_SummedInputWeightIsLessThanSummedOutputWeight() public {
        // arrange
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            address(0),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            generateMerkleRoot(),
            true,
            false
        );

        milady.setApprovalForAll(address(privatePool), true);

        inputTokenIds.push(1);
        inputTokenWeights.push(1.1e18);

        milady.mint(address(privatePool), 8);
        outputTokenIds.push(8);
        outputTokenWeights.push(1.11e18);

        inputProof = generateMerkleProofs(inputTokenIds, inputTokenWeights);
        outputProof = generateMerkleProofs(outputTokenIds, outputTokenWeights);

        (uint256 feeAmount,) = privatePool.changeFeeQuote(1.11e18);

        // act
        vm.expectRevert(PrivatePool.InsufficientInputWeight.selector);
        privatePool.change{value: feeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );
    }

    function test_RevertIf_InvalidMerkleProof() public {
        // arrange
        privatePool = new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        privatePool.initialize(
            address(0),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            generateMerkleRoot(),
            true,
            false
        );

        milady.setApprovalForAll(address(privatePool), true);

        inputTokenIds.push(1);
        inputTokenWeights.push(1.1e18);

        milady.mint(address(privatePool), 8);
        outputTokenIds.push(8);
        outputTokenWeights.push(1.11e18);

        inputProof = generateMerkleProofs(inputTokenIds, inputTokenWeights);
        outputProof = generateMerkleProofs(outputTokenIds, outputTokenWeights);
        inputTokenWeights[0] = 1.2e18;

        (uint256 feeAmount,) = privatePool.changeFeeQuote(1.11e18);

        // act
        vm.expectRevert(PrivatePool.InvalidMerkleProof.selector);
        privatePool.change{value: feeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );
    }

    function test_RevertIf_NftsAreMarkedAsStolen() public {
        // arrange
        inputTokenIds.push(0);
        inputTokenIds.push(1);
        inputTokenIds.push(2);

        outputTokenIds.push(3);
        outputTokenIds.push(4);
        outputTokenIds.push(5);
        (uint256 feeAmount,) = privatePool.changeFeeQuote(outputTokenIds.length * 1e18);
        stolenNftOracle.setStolenNft(address(milady), 2);

        // act
        vm.expectRevert(StolenNftOracle.StolenNft.selector);
        privatePool.change{value: feeAmount}(
            inputTokenIds,
            inputTokenWeights,
            inputProof,
            stolenNftProofs,
            outputTokenIds,
            outputTokenWeights,
            outputProof
        );
    }
}
