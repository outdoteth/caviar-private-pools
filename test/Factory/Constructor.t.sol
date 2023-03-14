// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract ConstructorTest is Fixture {
    function test_InitsParameters() public {
        // arrange
        address privatePoolImplementation = address(0x123);
        uint16 protocolFeeRate = 10;

        // act
        factory = new Factory();
        factory.setPrivatePoolImplementation(address(privatePoolImplementation));
        factory.setProtocolFeeRate(protocolFeeRate);

        // assert
        assertEq(
            factory.privatePoolImplementation(),
            privatePoolImplementation,
            "Should have initialized privatePoolImplementation"
        );

        assertEq(factory.protocolFeeRate(), protocolFeeRate, "Should have initialized protocolFeeRate");
    }
}
