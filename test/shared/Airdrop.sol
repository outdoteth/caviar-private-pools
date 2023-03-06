// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Airdrop {
    error SomeError();

    mapping(uint256 => bool) public claimed;

    function emptyRevert() public pure {
        revert();
    }

    function revertWithSomeError() public pure {
        revert SomeError();
    }

    function claim(uint256 tokenId) public payable returns (uint256) {
        claimed[tokenId] = true;
        return tokenId;
    }
}
