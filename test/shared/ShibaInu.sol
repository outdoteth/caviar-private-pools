// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "solmate/tokens/ERC20.sol";

contract ShibaInu is ERC20 {
    constructor() ERC20("Shiba Inu", "SHIB", 18) {}
}
