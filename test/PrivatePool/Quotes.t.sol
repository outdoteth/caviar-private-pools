// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract QuotesTest is Fixture {
    using stdStorage for StdStorage;

    PrivatePool public privatePool;

    address baseToken = address(0);
    address nft = address(milady);
    uint128 virtualBaseTokenReserves = 100e18;
    uint128 virtualNftReserves = 5e18;
    uint16 feeRate = 200;
    bytes32 merkleRoot = bytes32(0);
    address owner = address(this);

    uint256[] tokenIds;
    uint256[] tokenWeights;
    PrivatePool.MerkleMultiProof proofs;

    function setUp() public {
        privatePool = new PrivatePool(address(factory));
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, feeRate, merkleRoot, address(stolenNftOracle)
        );

        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ERC721.ownerOf.selector, address(privatePool)),
            abi.encode(address(this))
        );

        for (uint256 i = 0; i < 5; i++) {
            milady.mint(address(privatePool), i);
        }
    }

    function test_buyQuote_ReturnsNetInputAmount() public {
        // arrange
        uint256 outputAmount = 1e18;
        uint256 inputAmount = outputAmount * virtualBaseTokenReserves / (virtualNftReserves - outputAmount);
        uint256 feeAmount = inputAmount * 2 / 100; // 2%

        // act
        (uint256 returnedNetInputAmount, uint256 returnedFeeAmount) = privatePool.buyQuote(outputAmount);

        // assert
        assertEq(returnedNetInputAmount, inputAmount + feeAmount, "Should have returned netInputAmount");
        assertEq(returnedFeeAmount, feeAmount, "Should have returned feeAmount");
        assertGt(returnedFeeAmount, 0, "Fee amount should be greater than 0");
        assertGt(returnedNetInputAmount, 0, "Net input amount should be greater than 0");
    }

    function test_buyQuote_RoundsUp() public {
        // arrange
        uint128 newVirtualBaseTokenReserves = 10;
        uint128 newVirtualNftReserves = 1000;
        privatePool.setVirtualReserves(newVirtualBaseTokenReserves, newVirtualNftReserves);

        uint256 outputAmount = 10;
        uint256 inputAmount = outputAmount * newVirtualBaseTokenReserves / (newVirtualNftReserves - outputAmount);
        uint256 feeAmount = inputAmount * feeRate / 1e4;

        // act
        (uint256 returnedNetInputAmount, uint256 returnedFeeAmount) = privatePool.buyQuote(outputAmount);

        // assert
        assertEq(returnedNetInputAmount, inputAmount + feeAmount + 1, "Should have returned netInputAmount");
        assertEq(returnedFeeAmount, 0, "Should have returned feeAmount");
        assertGt(returnedNetInputAmount, 0, "Net input amount should be greater than 0");
    }

    function test_sellQuote_ReturnsNetOutputAmount() public {
        // arrange
        uint256 inputAmount = 1e18;
        uint256 outputAmount = inputAmount * virtualBaseTokenReserves / (virtualNftReserves + inputAmount);
        uint256 feeAmount = outputAmount * feeRate / 1e4; // 2%

        // act
        (uint256 returnedNetOutputAmount, uint256 returnedFeeAmount) = privatePool.sellQuote(inputAmount);

        // assert
        assertEq(returnedNetOutputAmount, outputAmount - feeAmount, "Should have returned netOutputAmount");
        assertEq(returnedFeeAmount, feeAmount, "Should have returned feeAmount");
        assertGt(returnedFeeAmount, 0, "Fee amount should be greater than 0");
        assertGt(returnedNetOutputAmount, 0, "Net output amount should be greater than 0");
    }

    function test_changeFeeQuote_ReturnsFeeAmount() public {
        // arrange
        uint256 inputAmount = 1e18;
        uint256 feeAmount = (privatePool.price() * inputAmount * feeRate / 1e4) / 1e18;

        // act
        uint256 returnedFeeAmount = privatePool.changeFeeQuote(inputAmount);

        // assert
        assertEq(returnedFeeAmount, feeAmount, "Should have returned feeAmount");
        assertGt(returnedFeeAmount, 0, "Fee amount should be greater than 0");
    }

    function test_price_ReturnsPrice() public {
        // arrange
        uint256 price = virtualBaseTokenReserves * 1e18 / virtualNftReserves;

        // act
        uint256 returnedPrice = privatePool.price();

        // assert
        assertEq(returnedPrice, price, "Should have returned price");
    }

    function test_price_ReturnsPriceTo18DecimalsIfERC20() public {
        // arrange
        stdstore.target(address(privatePool)).sig(privatePool.baseToken.selector).checked_write(address(shibaInu));
        uint256 price = virtualBaseTokenReserves * 10 ** (36 - shibaInu.decimals()) / virtualNftReserves;

        // act
        uint256 returnedPrice = privatePool.price();

        // assert
        assertEq(returnedPrice, price, "Should have returned price to 18 decimals");
    }
}
