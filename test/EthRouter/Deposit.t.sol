// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract DepositTest is Fixture {
    PrivatePool privatePool = new PrivatePool();
    uint256[] public tokenIds;

    function setUp() public {
        for (uint256 i = 0; i < 2; i++) {
            milady.mint(address(this), i);
            tokenIds.push(i);
        }

        milady.setApprovalForAll(address(ethRouter), true);

        privatePool.initialize(
            address(0), address(milady), 100e18, 200e18, 10, bytes32(0), address(stolenNftOracle), address(this)
        );
    }

    function test_DepositsEthAndNftsToPool() public {
        // arrange
        uint256 depositAmount = 1e18;

        // act
        ethRouter.deposit{value: depositAmount}(
            payable(address(privatePool)), address(milady), tokenIds, 0, type(uint256).max, 0
        );

        // assert
        assertEq(address(privatePool).balance, depositAmount, "Should have deposited eth to pool");
        assertEq(milady.balanceOf(address(privatePool)), tokenIds.length, "Should have deposited nfts to pool");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(privatePool), "Should have deposited nft to pool");
        }
    }

    function test_RevertIf_PriceIsTooLarge() public {
        // arrange
        uint256 depositAmount = 1e18;
        uint256 price = privatePool.price();

        // act
        vm.expectRevert(EthRouter.PriceOutOfRange.selector);
        ethRouter.deposit{value: depositAmount}(
            payable(address(privatePool)), address(milady), tokenIds, price + 1, type(uint256).max, 0
        );
    }

    function test_RevertIf_PriceIsTooSmall() public {
        // arrange
        uint256 depositAmount = 1e18;
        uint256 price = privatePool.price();

        // act
        vm.expectRevert(EthRouter.PriceOutOfRange.selector);
        ethRouter.deposit{value: depositAmount}(
            payable(address(privatePool)), address(milady), tokenIds, price, price - 1, 0
        );
    }

    function test_RevertIf_DeadlinePassed() public {
        // arrange
        uint256 depositAmount = 1e18;
        vm.warp(100);
        uint256 deadline = block.timestamp - 1;

        // act
        vm.expectRevert(EthRouter.DeadlinePassed.selector);
        ethRouter.deposit{value: depositAmount}(
            payable(address(privatePool)), address(milady), tokenIds, 0, type(uint256).max, deadline
        );
    }
}
