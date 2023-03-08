// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract BuyTest is Fixture {
    PrivatePool public privatePool;
    EthRouter.Buy[] public buys;
    uint256 public totalTokens = 0;
    uint256 public maxInputAmount = 0;

    function setUp() public {
        _addBuy();
        _addBuy();

        for (uint256 i = 0; i < buys.length; i++) {
            maxInputAmount += buys[i].baseTokenAmount;
        }
    }

    function _addBuy() internal {
        privatePool = new PrivatePool();
        privatePool.initialize(
            address(0), address(milady), 100e18, 10e18, 200, bytes32(0), address(stolenNftOracle), address(0xbabe)
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
                privatePool: payable(address(privatePool)),
                nft: address(milady),
                tokenIds: tokenIds,
                tokenWeights: new uint256[](0),
                proof: PrivatePool.MerkleMultiProof(new bytes32[](0), new bool[](0)),
                baseTokenAmount: baseTokenAmount
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
                buys[i].privatePool,
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
}
