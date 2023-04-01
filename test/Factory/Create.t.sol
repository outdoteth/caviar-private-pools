// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract CreateTest is Fixture {
    event Create(address indexed privatePool, uint256[] tokenIds, uint256 baseTokenAmount);

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100;
    uint128 virtualNftReserves = 200;
    uint16 feeRate = 10;
    uint56 changeFee = 255;
    bytes32 merkleRoot = bytes32(0);
    bytes32 salt = bytes32(0);
    uint256[] tokenIds;
    uint256 baseTokenAmount = 20;

    function setUp() public {
        privatePoolImplementation =
            new PrivatePool(address(factory), address(royaltyRegistry), address(stolenNftOracle));
        factory = new Factory();
        factory.setPrivatePoolImplementation(address(privatePoolImplementation));

        for (uint256 i = 0; i < 10; i++) {
            milady.mint(address(this), i);
        }

        milady.setApprovalForAll(address(factory), true);
    }

    function test_EmitsCreateEvent() public {
        // arrange
        address predictedAddress = factory.predictPoolDeploymentAddress(salt);
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);
        tokenIds.push(4);

        // act
        vm.expectEmit(true, true, true, true);
        emit Create(predictedAddress, tokenIds, baseTokenAmount);
        factory.create{value: baseTokenAmount}(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false,
            salt,
            tokenIds,
            baseTokenAmount
        );
    }

    function test_TransfersNftsFromCallerToPool() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);

        // act
        PrivatePool privatePool = factory.create{value: baseTokenAmount}(
            baseToken,
            address(milady),
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false,
            salt,
            tokenIds,
            baseTokenAmount
        );

        // assert
        assertEq(
            milady.balanceOf(address(privatePool)),
            tokenIds.length,
            "Should have transferred 3 NFTs tokens to the factory"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(privatePool), "Should have transferred the NFT to the pool");
        }
    }

    function test_TransfersEthToPool() public {
        // arrange
        baseTokenAmount = 1.123e18;

        // act
        PrivatePool privatePool = factory.create{value: baseTokenAmount}(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false,
            salt,
            tokenIds,
            baseTokenAmount
        );

        // assert
        assertEq(address(privatePool).balance, baseTokenAmount, "Should have transferred 1.123 ETH to the pool");
    }

    function test_TransfersBaseTokensFromCallerToPool() public {
        // arrange
        baseTokenAmount = 3.156e18;
        deal(address(shibaInu), address(this), baseTokenAmount);
        shibaInu.approve(address(factory), baseTokenAmount);

        // act
        PrivatePool privatePool = factory.create(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false,
            salt,
            tokenIds,
            baseTokenAmount
        );

        // assert
        assertEq(
            shibaInu.balanceOf(address(privatePool)), baseTokenAmount, "Should have transferred 3.156 SHIB to the pool"
        );
    }

    function test_MintsNftToCaller() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);

        // act
        PrivatePool privatePool = factory.create{value: baseTokenAmount}(
            baseToken,
            address(milady),
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false,
            salt,
            tokenIds,
            baseTokenAmount
        );

        // assert
        assertEq(
            factory.ownerOf(uint256(uint160(address(privatePool)))),
            address(this),
            "Should have minted NFT to the caller"
        );
    }

    function test_RevertIf_BaseTokenIsEthAndValueDoesNotEqualBaseTokenAmount() public {
        // arrange
        baseTokenAmount = 1.111e18;

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        factory.create{value: baseTokenAmount + 1}(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false,
            salt,
            tokenIds,
            baseTokenAmount
        );
    }

    function test_RevertIf_BaseTokenIsNotEthAndValueIsGreaterThanZero() public {
        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        factory.create{value: 100}(
            address(shibaInu),
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            changeFee,
            feeRate,
            merkleRoot,
            true,
            false,
            salt,
            tokenIds,
            baseTokenAmount
        );
    }
}
