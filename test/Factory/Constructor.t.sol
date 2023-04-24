// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Fixture.sol";

contract ConstructorTest is Fixture {
    function test_InitsParameters() public {
        // arrange
        address privatePoolImplementation = address(0x123);
        uint16 protocolFeeRate = 10;
        uint16 protocolChangeFeeRate = 255;

        // act
        factory = new Factory();
        factory.setPrivatePoolImplementation(address(privatePoolImplementation));
        factory.setProtocolFeeRate(protocolFeeRate);
        factory.setProtocolChangeFeeRate(protocolChangeFeeRate);

        // assert
        assertEq(
            factory.privatePoolImplementation(),
            privatePoolImplementation,
            "Should have initialized privatePoolImplementation"
        );
        assertEq(factory.protocolFeeRate(), protocolFeeRate, "Should have initialized protocolFeeRate");
        assertEq(
            factory.protocolChangeFeeRate(), protocolChangeFeeRate, "Should have initialized protocolChangeFeeRate"
        );
    }

    function test_RevertIf_ProtocolFeeRateIsTooHigh() public {
        // arrange
        uint16 protocolFeeRate = 501;

        // act
        factory = new Factory();
        vm.expectRevert(Factory.ProtocolFeeRateTooHigh.selector);
        factory.setProtocolFeeRate(protocolFeeRate);
    }

    function test_RevertIf_ProtocolChangeFeeRateIsTooHigh() public {
        // arrange
        uint16 protocolChangeFeeRate = 10_001;

        // act
        factory = new Factory();
        vm.expectRevert(Factory.ProtocolChangeFeeRateTooHigh.selector);
        factory.setProtocolChangeFeeRate(protocolChangeFeeRate);
    }
}
