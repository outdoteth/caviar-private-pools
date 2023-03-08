// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract CreateTest is Fixture {
    event Create(address indexed privatePool, uint256[] indexed tokenIds, uint256 indexed baseTokenAmount);

    address baseToken = address(0);
    address nft = address(0);
    uint128 virtualBaseTokenReserves = 100;
    uint128 virtualNftReserves = 200;
    uint16 feeRate = 10;
    bytes32 merkleRoot = bytes32(0);
    bytes32 salt = bytes32(0);
    uint256[] tokenIds;
    uint256 baseTokenAmount;

    function setUp() public {
        privatePoolImplementation = new PrivatePool();
        factory = new Factory(address(privatePoolImplementation));

        for (uint256 i = 0; i < 10; i++) {
            milady.mint(address(this), i);
        }

        milady.setApprovalForAll(address(factory), true);
    }

    function test_EmitsCreateEvent() public {
        // arrange
        address predictedAddress = factory.predictPoolDeploymentAddress(salt, address(factory));

        // act
        vm.expectEmit(true, true, true, true);
        emit Create(predictedAddress, tokenIds, baseTokenAmount);
        factory.create(
            baseToken,
            nft,
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
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
        PrivatePool privatePool = factory.create(
            baseToken,
            address(milady),
            virtualBaseTokenReserves,
            virtualNftReserves,
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
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
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
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
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            salt,
            tokenIds,
            baseTokenAmount
        );

        // assert
        assertEq(
            shibaInu.balanceOf(address(privatePool)), baseTokenAmount, "Should have transferred 3.156 SHIB to the pool"
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
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
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
            feeRate,
            merkleRoot,
            address(stolenNftOracle),
            salt,
            tokenIds,
            baseTokenAmount
        );
    }
}
