// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract NftTest is Fixture {
    function test_setPrivatePoolMetadata_SetsPrivatePoolMetadata() public {
        // arrange
        address privatePoolMetadata = address(0xbabebabebabe);

        // act
        factory.setPrivatePoolMetadata(privatePoolMetadata);

        // assert
        assertEq(factory.privatePoolMetadata(), privatePoolMetadata, "Should have set private pool metadata");
    }

    function test_RevertIf_setPrivatePoolMetadata_CallerIsNotOwner() public {
        // arrange
        address user = address(0xbabe);
        address privatePoolMetadata = address(0x123);

        // act
        vm.prank(user);
        vm.expectRevert("UNAUTHORIZED");
        factory.setPrivatePoolMetadata(privatePoolMetadata);
    }

    function test_tokenURI_ReturnsTokenURI() public {
        // arrange
        PrivatePool privatePool = new PrivatePool(address(factory));
        privatePool.initialize(address(0), address(milady), 100e18, 20e18, 2000, bytes32(0), address(stolenNftOracle));
        payable(address(privatePool)).transfer(0.1 ether);
        milady.mint(address(privatePool), 1);
        milady.mint(address(privatePool), 2);
        uint256 tokenId = uint160(address(privatePool));

        // act
        string memory tokenURI = factory.tokenURI(tokenId);

        // console.log(tokenURI);
    }
}
