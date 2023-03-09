// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract DepositTest is Fixture {
    event Deposit(uint256[] tokenIds, uint256 baseTokenAmount);

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
            milady.mint(address(this), i);
        }

        milady.setApprovalForAll(address(privatePool), true);
    }

    function test_EmitsDepositEvent() public {
        // arrange
        uint256 baseTokenAmount = 1e18;

        // act
        vm.expectEmit(true, true, true, true);
        emit Deposit(tokenIds, baseTokenAmount);
        privatePool.deposit{value: baseTokenAmount}(tokenIds, baseTokenAmount);
    }

    function test_TransfersEthFromCaller() public {
        // arrange
        uint256 baseTokenAmount = 3.156e18;

        // act
        privatePool.deposit{value: baseTokenAmount}(tokenIds, baseTokenAmount);

        // assert
        assertEq(address(privatePool).balance, baseTokenAmount, "Should have deposited baseTokenAmount");
    }

    function test_TransfersBaseTokensFromCaller() public {
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
        uint256 baseTokenAmount = 3.156e18;
        deal(address(shibaInu), address(this), baseTokenAmount);
        shibaInu.approve(address(privatePool), baseTokenAmount);

        // act
        privatePool.deposit(tokenIds, baseTokenAmount);

        // assert
        assertEq(shibaInu.balanceOf(address(privatePool)), baseTokenAmount, "Should have deposited baseTokenAmount");
    }

    function test_TransfersNftsFromCaller() public {
        // arrange
        tokenIds.push(1);
        tokenIds.push(2);
        tokenIds.push(3);

        // act
        privatePool.deposit(tokenIds, 0);

        // assert
        assertEq(
            milady.balanceOf(address(privatePool)), tokenIds.length, "Should have deposited tokenIds.length tokens"
        );
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(milady.ownerOf(tokenIds[i]), address(privatePool), "Should have deposited tokenIds[i] token");
        }
    }

    function test_RevertIf_BaseTokenIsEthAndValueIsNotEqualToBaseTokenAmount() public {
        // arrange
        uint256 baseTokenAmount = 1e18;

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.deposit{value: baseTokenAmount - 1}(tokenIds, baseTokenAmount);
    }

    function test_RevertIf_BaseTokenIsNotEthAndValueIsGreaterThanZero() public {
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
        uint256 baseTokenAmount = 1e18;

        // act
        vm.expectRevert(PrivatePool.InvalidEthAmount.selector);
        privatePool.deposit{value: baseTokenAmount}(tokenIds, baseTokenAmount);
    }

    function testFuzz_EmitsDepositEvent(uint256[] calldata _tokenIds, uint256 _baseTokenAmount) public {
        // arrange
        deal(address(this), _baseTokenAmount);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (!existingTokenIds[_tokenIds[i]] && _tokenIds[i] > 5) {
                milady.mint(address(this), _tokenIds[i]);
                tokenIds.push(_tokenIds[i]);
                existingTokenIds[_tokenIds[i]] = true;
            }
        }

        // act
        vm.expectEmit(true, true, true, true);
        emit Deposit(tokenIds, _baseTokenAmount);
        privatePool.deposit{value: _baseTokenAmount}(tokenIds, _baseTokenAmount);
    }
}
