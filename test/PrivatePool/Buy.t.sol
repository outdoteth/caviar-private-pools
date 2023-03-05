// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";
import "../../src/PrivatePool.sol";

contract BuyTest is Fixture {
    PrivatePool public privatePool;

    address baseToken = address(0x123);
    address nft = address(0x456);
    uint128 virtualBaseTokenReserves = 100;
    uint128 virtualNftReserves = 500;
    uint16 feeRate = 0;
    bytes32 merkleRoot = bytes32(abi.encode(0));
    address stolenNftOracle = address(0);
    address owner = address(this);

    function setUp() public {
        privatePool = new PrivatePool();
        privatePool.initialize(
            baseToken, nft, virtualBaseTokenReserves, virtualNftReserves, feeRate, merkleRoot, stolenNftOracle, owner
        );
    }
}
