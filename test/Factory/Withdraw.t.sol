// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract WithdrawTest is Fixture {
    event Withdraw(address indexed token, uint256 indexed amount);

    function test_EmitsWithdrawEvent() public {
        // arrange
        address token = address(0);
        uint256 amount = 100;
        deal(address(factory), amount);

        // act
        vm.expectEmit(true, true, true, true);
        emit Withdraw(token, amount);
        factory.withdraw(token, amount);
    }

    function test_TransfersTokensToCaller() public {
        // arrange
        address token = address(shibaInu);
        uint256 amount = 100;
        deal(address(shibaInu), address(factory), amount);

        // act
        factory.withdraw(token, amount);

        // assert
        assertEq(shibaInu.balanceOf(address(factory)), 0, "Should have transferred tokens to caller");
        assertEq(shibaInu.balanceOf(address(this)), amount, "Should have transferred tokens to caller");
    }

    function test_WithdrawsEthToCaller() public {
        // arrange
        address token = address(0);
        uint256 amount = 100;
        deal(address(factory), amount);
        uint256 balanceBefore = address(this).balance;

        // act
        factory.withdraw(token, amount);

        // assert
        assertEq(address(this).balance - balanceBefore, amount, "Should have transferred eth to caller");
        assertEq(address(factory).balance, 0, "Should have transferred eth to caller");
    }

    function test_RevertIf_NotOwner() public {
        // act
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(address(0xbabe));
        factory.withdraw(address(0), 100);
    }
}
