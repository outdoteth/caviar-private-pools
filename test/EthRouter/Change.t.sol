// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract ChangeTest is Fixture {
    PrivatePool public privatePool =
        new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
    EthRouter.Change[] public changes;

    function setUp() public {
        privatePool.initialize(address(0), address(milady), 10e18, 10e18, 50000, 1999, bytes32(0), true, false);

        for (uint256 i = 0; i < 5; i++) {
            milady.mint(address(privatePool), i);
        }

        for (uint256 i = 5; i < 10; i++) {
            milady.mint(address(this), i);
        }

        milady.setApprovalForAll(address(ethRouter), true);
    }

    function test_RefundsSurplusEth() public {
        uint256[] memory inputTokenIds = new uint256[](5);
        uint256[] memory inputTokenWeights = new uint256[](0);
        uint256[] memory outputTokenIds = new uint256[](5);
        uint256[] memory outputTokenWeights = new uint256[](0);

        for (uint256 i = 0; i < 5; i++) {
            inputTokenIds[i] = i + 5;
            outputTokenIds[i] = i;
        }

        changes.push(
            EthRouter.Change({
                pool: payable(address(privatePool)),
                nft: address(milady),
                inputTokenIds: inputTokenIds,
                inputTokenWeights: inputTokenWeights,
                inputProof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
                outputTokenIds: outputTokenIds,
                outputTokenWeights: outputTokenWeights,
                outputProof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0))
            })
        );

        (uint256 changeFee,) = privatePool.changeFeeQuote(inputTokenIds.length * 1e18);
        uint256 balanceBefore = address(this).balance;

        // act
        ethRouter.change{value: changeFee + 1000}(changes, 0);

        // assert
        assertEq(balanceBefore - address(this).balance, changeFee, "Should have refunded surplus eth");
    }

    function test_ChangesInputNftsForOutputNfts() public {
        uint256[] memory inputTokenIds = new uint256[](5);
        uint256[] memory inputTokenWeights = new uint256[](0);
        uint256[] memory outputTokenIds = new uint256[](5);
        uint256[] memory outputTokenWeights = new uint256[](0);

        for (uint256 i = 0; i < 5; i++) {
            inputTokenIds[i] = i + 5;
            outputTokenIds[i] = i;
        }

        changes.push(
            EthRouter.Change({
                pool: payable(address(privatePool)),
                nft: address(milady),
                inputTokenIds: inputTokenIds,
                inputTokenWeights: inputTokenWeights,
                inputProof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
                outputTokenIds: outputTokenIds,
                outputTokenWeights: outputTokenWeights,
                outputProof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0))
            })
        );

        (uint256 changeFee,) = privatePool.changeFeeQuote(inputTokenIds.length * 1e18);

        // act
        ethRouter.change{value: changeFee}(changes, 0);

        // assert
        for (uint256 i = 0; i < 5; i++) {
            assertEq(milady.ownerOf(i), address(this), "Should have changed nft to user");
        }

        for (uint256 i = 5; i < 10; i++) {
            assertEq(milady.ownerOf(i), address(privatePool), "Should have changed nft to pool");
        }
    }

    function test_CallsChangeWithData() public {
        uint256[] memory inputTokenIds = new uint256[](5);
        uint256[] memory inputTokenWeights = new uint256[](0);
        uint256[] memory outputTokenIds = new uint256[](5);
        uint256[] memory outputTokenWeights = new uint256[](0);

        for (uint256 i = 0; i < 5; i++) {
            inputTokenIds[i] = i + 5;
            outputTokenIds[i] = i;
        }

        changes.push(
            EthRouter.Change({
                pool: payable(address(privatePool)),
                nft: address(milady),
                inputTokenIds: inputTokenIds,
                inputTokenWeights: inputTokenWeights,
                inputProof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
                outputTokenIds: outputTokenIds,
                outputTokenWeights: outputTokenWeights,
                outputProof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0))
            })
        );

        (uint256 changeFee,) = privatePool.changeFeeQuote(inputTokenIds.length * 1e18);

        // act
        vm.expectCall(
            address(privatePool),
            abi.encodeCall(
                PrivatePool.change,
                (
                    changes[0].inputTokenIds,
                    changes[0].inputTokenWeights,
                    changes[0].inputProof,
                    changes[0].outputTokenIds,
                    changes[0].outputTokenWeights,
                    changes[0].outputProof
                )
            )
        );
        ethRouter.change{value: changeFee}(changes, 0);
    }

    function test_RevertIf_DeadlinePassed() public {
        // act
        vm.warp(100);
        vm.expectRevert(EthRouter.DeadlinePassed.selector);
        ethRouter.change(changes, block.timestamp - 10);
    }
}
