// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "solmate/tokens/ERC721.sol";

contract Milady is ERC721 {
    constructor() ERC721("Milady Maker", "MIL") {}

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "https://milady.io";
    }

    function mint(address to, uint256 id) public {
        _mint(to, id);
    }
}
