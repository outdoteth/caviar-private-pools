// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract WithdrawTest is Fixture {
    event Withdraw(address indexed nft, uint256[] tokenIds, address token, uint256 amount);

    PrivatePool public privatePool;

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100e18;
    uint128 virtualNftReserves = 5e18;
    uint16 feeRate = 0;
    bytes32 merkleRoot = bytes32(0);
    address owner = address(this);

    uint256[] tokenIds;
    uint256[] tokenWeights;
    bytes32[][] proofs;

    mapping(uint256 => bool) existingTokenIds;

    function setUp() public {
        privatePool = new PrivatePool(address(factory));
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, feeRate, merkleRoot, address(stolenNftOracle)
        );

        for (uint256 i = 0; i < 5; i++) {
            milady.mint(address(privatePool), i);
        }

        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ERC721.ownerOf.selector, address(privatePool)),
            abi.encode(address(this))
        );
    }

    function test_EmitsWithdrawEvent() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        uint256 tokenAmount = 123;
        deal(address(privatePool), tokenAmount);

        // act
        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(nft), tokenIds, address(0), tokenAmount);
        privatePool.withdraw(address(nft), tokenIds, address(0), tokenAmount);
    }

    function test_TransfersBaseTokensToCaller() public {
        // arrange
        privatePool = new PrivatePool(address(factory));
        privatePool.initialize(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle)
        );

        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ERC721.ownerOf.selector, address(privatePool)),
            abi.encode(address(this))
        );

        milady.mint(address(privatePool), 6);
        milady.mint(address(privatePool), 7);
        milady.mint(address(privatePool), 8);

        tokenIds.push(6);
        tokenIds.push(7);
        tokenIds.push(8);
        uint256 tokenAmount = 123;
        deal(address(shibaInu), address(privatePool), tokenAmount);

        // act
        privatePool.withdraw(address(nft), tokenIds, address(shibaInu), tokenAmount);

        // assert
        assertEq(shibaInu.balanceOf(address(this)), tokenAmount, "Should have transferred base tokens to caller");
    }

    function test_TransfersEthToCaller() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        uint256 tokenAmount = 123;
        deal(address(privatePool), tokenAmount);
        uint256 balanceBefore = address(this).balance;

        // act
        privatePool.withdraw(address(nft), tokenIds, address(0), tokenAmount);

        // assert
        assertEq(address(this).balance - balanceBefore, tokenAmount, "Should have transferred eth to caller");
    }

    function test_TransfersNftsToCaller() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        uint256 tokenAmount = 123;
        deal(address(privatePool), tokenAmount);

        // act
        privatePool.withdraw(address(nft), tokenIds, address(0), tokenAmount);

        // assert
        assertEq(milady.balanceOf(address(this)), tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(this), "Should have transferred nfts to caller");
        }
    }
}
