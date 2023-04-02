// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract SellTest is Fixture {
    PrivatePool public privatePool;
    uint256 public totalTokens = 0;
    uint256 public minOutputAmount = 0;

    function setUp() public {
        milady.setApprovalForAll(address(ethRouter), true);
    }

    function _addSell() internal returns (EthRouter.Sell memory, uint256) {
        uint256[] memory empty = new uint256[](0);
        privatePool = factory.create{value: 100e18}(
            address(0),
            address(milady),
            100e18,
            10e18,
            200,
            199,
            bytes32(0),
            true,
            false,
            bytes32(address(this).balance), // random between each call to _addBuy
            empty,
            100e18
        );

        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            milady.mint(address(this), i + totalTokens);
            tokenIds[i] = i + totalTokens;
        }

        totalTokens += 2;

        bytes32[][] memory publicPoolProofs = new bytes32[][](0);
        EthRouter.Sell memory sell = EthRouter.Sell({
            pool: payable(address(privatePool)),
            nft: address(milady),
            tokenIds: tokenIds,
            tokenWeights: new uint256[](0),
            proof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
            stolenNftProofs: new IStolenNftOracle.Message[](0),
            isPublicPool: false,
            publicPoolProofs: publicPoolProofs
        });

        (uint256 baseTokenAmount,,) = privatePool.sellQuote(tokenIds.length * 1e18);
        return (sell, baseTokenAmount);
    }

    function test_TransfersOutputAmountToCaller() public {
        // arrange
        EthRouter.Sell[] memory sells = new EthRouter.Sell[](2);
        (EthRouter.Sell memory sell1, uint256 outputAmount1) = _addSell();
        (EthRouter.Sell memory sell2, uint256 outputAmount2) = _addSell();
        minOutputAmount += outputAmount1 + outputAmount2;
        sells[0] = sell1;
        sells[1] = sell2;
        uint256 balanceBefore = address(this).balance;

        // act
        ethRouter.sell(sells, minOutputAmount, 0, false);

        // assert
        assertEq(
            address(this).balance - balanceBefore, minOutputAmount, "Should have transferred output amount to caller"
        );
    }

    function test_RevertIf_OutputAmountIsTooSmall() public {
        // arrange
        EthRouter.Sell[] memory sells = new EthRouter.Sell[](2);
        (EthRouter.Sell memory sell1, uint256 outputAmount1) = _addSell();
        (EthRouter.Sell memory sell2, uint256 outputAmount2) = _addSell();
        minOutputAmount += outputAmount1 + outputAmount2;
        sells[0] = sell1;
        sells[1] = sell2;

        // act
        vm.expectRevert(EthRouter.OutputAmountTooSmall.selector);
        ethRouter.sell(sells, minOutputAmount + 100, 0, false);
    }

    function test_CallsPrivatePoolWithSellData() public {
        // arrange
        EthRouter.Sell[] memory sells = new EthRouter.Sell[](2);
        (EthRouter.Sell memory sell1, uint256 outputAmount1) = _addSell();
        (EthRouter.Sell memory sell2, uint256 outputAmount2) = _addSell();
        minOutputAmount += outputAmount1 + outputAmount2;
        sells[0] = sell1;
        sells[1] = sell2;

        // act
        for (uint256 i = 0; i < sells.length; i++) {
            vm.expectCall(
                sells[i].pool,
                0,
                abi.encodeWithSelector(
                    PrivatePool.sell.selector,
                    sells[i].tokenIds,
                    sells[i].tokenWeights,
                    sells[i].proof,
                    sells[i].stolenNftProofs
                )
            );
        }
        ethRouter.sell(sells, minOutputAmount, 0, false);
    }

    function test_CallsApproveForEachPrivatePool() public {
        // arrange
        EthRouter.Sell[] memory sells = new EthRouter.Sell[](2);
        (EthRouter.Sell memory sell1, uint256 outputAmount1) = _addSell();
        (EthRouter.Sell memory sell2, uint256 outputAmount2) = _addSell();
        minOutputAmount += outputAmount1 + outputAmount2;
        sells[0] = sell1;
        sells[1] = sell2;

        // act
        for (uint256 i = 0; i < sells.length; i++) {
            vm.expectCall(
                address(milady), 0, abi.encodeWithSelector(ERC721.setApprovalForAll.selector, sells[i].pool, true)
            );
        }
        ethRouter.sell(sells, minOutputAmount, 0, false);
    }

    function test_RevertIf_DeadlineHasPassed() public {
        // arrange
        EthRouter.Sell[] memory sells = new EthRouter.Sell[](2);

        // act
        vm.expectRevert(EthRouter.DeadlinePassed.selector);
        vm.warp(100);
        ethRouter.sell(sells, minOutputAmount, block.timestamp - 1, false);
    }

    function test_SellsToPublicPool() public {
        // arrange
        EthRouter.Sell[] memory sells = new EthRouter.Sell[](3);
        (EthRouter.Sell memory sell1, uint256 outputAmount1) = _addSell();
        (EthRouter.Sell memory sell2, uint256 outputAmount2) = _addSell();
        minOutputAmount += outputAmount1 + outputAmount2;
        sells[0] = sell1;
        sells[1] = sell2;
        Pair pair = caviar.create(address(milady), address(0), bytes32(0));
        deal(address(pair), 1.123e18);
        deal(address(pair), address(pair), 10e18);

        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenIds[i] = i + totalTokens;
            milady.mint(address(this), i + totalTokens);
        }
        sells[2] = EthRouter.Sell({
            pool: payable(address(pair)),
            nft: address(milady),
            tokenIds: tokenIds,
            tokenWeights: new uint256[](0),
            proof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
            stolenNftProofs: new IStolenNftOracle.Message[](0),
            isPublicPool: true,
            publicPoolProofs: new bytes32[][](0)
        });

        uint256 outputAmount = pair.sellQuote(tokenIds.length * 1e18);
        minOutputAmount += outputAmount;
        uint256 balanceBefore = address(this).balance;

        // act
        vm.expectCall(
            address(pair),
            0,
            abi.encodeWithSelector(
                Pair.nftSell.selector, tokenIds, 0, 0, new bytes32[][](0), new IStolenNftOracle.Message[](0)
            )
        );
        ethRouter.sell(sells, minOutputAmount, 0, false);

        // assert
        assertEq(
            address(this).balance - balanceBefore, minOutputAmount, "Should have transferred output amount to caller"
        );

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(pair), "Should have transferred NFT to public pool");
        }
    }

    function test_PaysRoyalties() public {
        // arrange
        EthRouter.Sell[] memory sells = new EthRouter.Sell[](3);
        (EthRouter.Sell memory sell1, uint256 outputAmount1) = _addSell();
        (EthRouter.Sell memory sell2, uint256 outputAmount2) = _addSell();
        minOutputAmount += outputAmount1 + outputAmount2;
        sells[0] = sell1;
        sells[1] = sell2;
        Pair pair = caviar.create(address(milady), address(0), bytes32(0));
        deal(address(pair), 1.123e18);
        deal(address(pair), address(pair), 10e18);

        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenIds[i] = i + totalTokens;
            milady.mint(address(this), i + totalTokens);
        }
        sells[2] = EthRouter.Sell({
            pool: payable(address(pair)),
            nft: address(milady),
            tokenIds: tokenIds,
            tokenWeights: new uint256[](0),
            proof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
            stolenNftProofs: new IStolenNftOracle.Message[](0),
            isPublicPool: true,
            publicPoolProofs: new bytes32[][](0)
        });

        uint256 outputAmount = pair.sellQuote(tokenIds.length * 1e18);

        uint256 royaltyFeeRate = 0.1e18; // 10%
        address royaltyRecipient = address(0xbeefbeef);
        milady.setRoyaltyInfo(royaltyFeeRate, royaltyRecipient);

        uint256 royaltyFee = outputAmount / tokenIds.length * royaltyFeeRate / 1e18 * tokenIds.length;
        outputAmount -= royaltyFee;
        minOutputAmount += outputAmount;

        // act
        ethRouter.sell(sells, minOutputAmount, 0, true);

        // assert
        assertEq(address(royaltyRecipient).balance, royaltyFee, "Should have paid royalties");
    }
}
