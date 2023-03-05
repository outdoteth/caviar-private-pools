// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "solmate/tokens/ERC721.sol";

import "./shared/Milady.sol";
import "./shared/ShibaInu.sol";

contract Fixture is Test, ERC721TokenReceiver {
    using stdStorage for StdStorage;

    Milady public milady = new Milady();
    ShibaInu public shibaInu = new ShibaInu();

    constructor() {}

    receive() external payable {}
}
