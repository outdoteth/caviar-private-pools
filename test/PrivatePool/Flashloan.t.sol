// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../shared/FlashBorrower.sol";
import "../../src/PrivatePool.sol";

contract FlashloanTest is Fixture {
    using stdStorage for StdStorage;

    FlashBorrower flashBorrower;
    PrivatePool privatePool;

    function setUp() public {
        privatePool = factory.create{value: 1e18}(
            address(0),
            address(milady),
            100e18,
            10e18,
            200,
            100,
            bytes32(0),
            true,
            false,
            bytes32(address(this).balance),
            new uint256[](0),
            1e18
        );

        milady.mint(address(privatePool), 1);

        flashBorrower = new FlashBorrower(privatePool);
    }

    function test_PaysFlashLoanFee() public {
        // arrange
        uint256 fee = privatePool.flashFee(address(milady), 1);
        deal(address(flashBorrower), fee);
        uint256 balanceBefore = address(privatePool).balance;

        // act
        flashBorrower.initiateFlashLoan(address(milady), 1, "");

        // assert
        assertEq(address(privatePool).balance, balanceBefore + fee, "Should have paid fee");
        assertGt(address(privatePool).balance, 0, "Should have paid fee");
    }

    function test_PaysFlashLoanFeeWithBaseToken() public {
        // arrange
        stdstore.target(address(privatePool)).sig("baseToken()").checked_write(address(shibaInu));
        uint256 fee = privatePool.flashFee(address(0), 1);
        deal(address(shibaInu), address(flashBorrower), fee);
        uint256 balanceBefore = shibaInu.balanceOf(address(privatePool));

        // act
        flashBorrower.initiateFlashLoan(address(milady), 1, "");

        // assert
        assertEq(shibaInu.balanceOf(address(privatePool)), balanceBefore + fee, "Should have paid fee");
    }
}
