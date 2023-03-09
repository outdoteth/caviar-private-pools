// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract ExecuteTest is Fixture {
    PrivatePool public privatePool;

    address owner = address(this);

    function setUp() public {
        privatePool = new PrivatePool(address(factory));
        privatePool.initialize(address(0), address(0), 0, 0, 0, bytes32(0), address(stolenNftOracle));

        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ERC721.ownerOf.selector, address(privatePool)),
            abi.encode(address(this))
        );
    }

    function test_RevertIf_NotOwner() public {
        // arrange
        address user = address(0x123);
        bytes memory data = "";

        // act
        vm.prank(user);
        vm.expectRevert(PrivatePool.Unauthorized.selector);
        privatePool.execute(address(0xbabe), data);
    }

    function test_ItReturnsData() public {
        // arrange
        uint256 tokenId = 1;

        // act
        bytes memory returnData = privatePool.execute(address(airdrop), abi.encodeCall(Airdrop.claim, (1)));

        // assert
        assertEq(returnData, abi.encode(tokenId), "Should have succeeded");
    }

    function test_RevertIf_TargetRevertsWithZeroData() public {
        // act
        vm.expectRevert(bytes(""));
        privatePool.execute(address(airdrop), abi.encodeCall(Airdrop.emptyRevert, ()));
    }

    function test_RevertIf_TargetRevertsWithData() public {
        // act
        vm.expectRevert(Airdrop.SomeError.selector);
        privatePool.execute(address(airdrop), abi.encodeCall(Airdrop.revertWithSomeError, ()));
    }

    function test_MarksClaimedAsTrueAfterClaimingAirdrop() public {
        // arrange
        uint256 tokenId = 1;

        // act
        privatePool.execute(address(airdrop), abi.encodeCall(Airdrop.claim, (1)));

        // assert
        assertTrue(airdrop.claimed(tokenId), "Should have claimed");
    }

    function test_ForwardsValueToAirdrop() public {
        // arrange
        uint256 value = 100;
        uint256 balanceBefore = address(privatePool).balance;

        // act
        privatePool.execute{value: value}(address(airdrop), abi.encodeCall(Airdrop.claim, (1)));

        // assert
        assertEq(address(airdrop).balance, value, "Should have forwarded value");
        assertEq(address(privatePool).balance, balanceBefore, "Private pool balance should have remained the same");
    }
}
