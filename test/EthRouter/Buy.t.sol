// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract BuyTest is Fixture {
    PrivatePool public privatePool;
    EthRouter.Buy[] public buys;
    uint256 public totalTokens = 0;
    uint256 public maxInputAmount = 0;

    function setUp() public {
        deal(address(this), 10000000e18);

        _addBuy();
        _addBuy();

        for (uint256 i = 0; i < buys.length; i++) {
            maxInputAmount += buys[i].baseTokenAmount;
        }
    }

    function _addBuy() internal {
        uint256[] memory empty = new uint256[](0);
        privatePool = factory.create{value: 1e18}(
            address(0),
            address(milady),
            100e18,
            10e18,
            200,
            bytes32(0),
            address(stolenNftOracle),
            bytes32(address(this).balance), // random between each call to _addBuy
            empty,
            1e18,
            false
        );
        uint256[] memory tokenIds = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            milady.mint(address(privatePool), i + totalTokens);
            tokenIds[i] = i + totalTokens;
        }

        totalTokens += 2;

        (uint256 baseTokenAmount,) = privatePool.buyQuote(tokenIds.length * 1e18);
        buys.push(
            EthRouter.Buy({
                pool: payable(address(privatePool)),
                nft: address(milady),
                tokenIds: tokenIds,
                tokenWeights: new uint256[](0),
                proof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
                baseTokenAmount: baseTokenAmount,
                isPublicPool: false
            })
        );
    }

    function test_RefundsExcessEth() public {
        // arrange
        uint256 balanceBefore = address(this).balance;

        // act
        ethRouter.buy{value: maxInputAmount + 1e18}(buys, 0);

        // assert
        assertEq(balanceBefore - address(this).balance, maxInputAmount, "Should have refunded excess ETH");
        assertEq(address(ethRouter).balance, 0, "Should have sent all eth from router");
    }

    function test_RevertIf_InputAmountIsLargerThanMax() public {
        // act
        vm.expectRevert();
        ethRouter.buy{value: maxInputAmount - 10}(buys, 0);
    }

    function test_TransfersNftsToCaller() public {
        // act
        ethRouter.buy{value: maxInputAmount}(buys, 0);

        // assert
        for (uint256 i = 0; i < buys.length; i++) {
            for (uint256 j = 0; j < buys[i].tokenIds.length; j++) {
                assertEq(milady.ownerOf(buys[i].tokenIds[j]), address(this), "Should have transferred NFT to caller");
            }
        }
    }

    function test_CallsPrivatePoolWithBuyData() public {
        // act
        for (uint256 i = 0; i < buys.length; i++) {
            vm.expectCall(
                buys[i].pool,
                buys[i].baseTokenAmount,
                abi.encodeWithSelector(PrivatePool.buy.selector, buys[i].tokenIds, buys[i].tokenWeights, buys[i].proof)
            );
        }
        ethRouter.buy{value: maxInputAmount}(buys, 0);
    }

    function test_RevertIf_DeadlinePassed() public {
        // act
        vm.expectRevert(EthRouter.DeadlinePassed.selector);
        vm.warp(100);
        ethRouter.buy{value: maxInputAmount}(buys, 99);
    }

    function test_PaysRoyalties() public {
        // arrange
        uint256 royaltyFeeRate = 0.1e18; // 10%
        address royaltyRecipient = address(0xbeefbeef);
        milady.setRoyaltyInfo(royaltyFeeRate, royaltyRecipient);
        uint256 royaltyFee = maxInputAmount * royaltyFeeRate / 1e18;
        maxInputAmount = maxInputAmount + royaltyFee;

        // act
        ethRouter.buy{value: maxInputAmount}(buys, 0);

        // assert
        assertEq(address(0xbeefbeef).balance, royaltyFee, "Should have paid royalties");
    }

    function test_BuysFromPublicPool() public {
        // arrange
        Pair pair = caviar.create(address(milady), address(0), bytes32(0));
        deal(address(pair), 1.123e18);
        deal(address(pair), address(pair), 10e18);

        uint256[] memory tokenIds = new uint256[](5);
        for (uint256 i = 0; i < 10; i++) {
            milady.mint(address(pair), i + totalTokens);
            if (i < 5) {
                tokenIds[i] = i + totalTokens;
            }
        }

        uint256 inputAmount = pair.buyQuote(tokenIds.length * 1e18);
        maxInputAmount += inputAmount;

        buys.push(
            EthRouter.Buy({
                pool: payable(address(pair)),
                nft: address(milady),
                tokenIds: tokenIds,
                tokenWeights: new uint256[](0),
                proof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
                baseTokenAmount: inputAmount,
                isPublicPool: true
            })
        );

        // act
        vm.expectCall(
            address(pair), inputAmount, abi.encodeWithSelector(Pair.nftBuy.selector, tokenIds, inputAmount, 0)
        );
        ethRouter.buy{value: maxInputAmount}(buys, 0);

        // assert
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(this), "Should have transferred NFT to caller");
        }
    }
}
