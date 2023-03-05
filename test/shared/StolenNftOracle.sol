// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IStolenNftOracle} from "../../src/interfaces/IStolenNftOracle.sol";

contract StolenNftOracle is IStolenNftOracle {
    error StolenNft();

    mapping(address => mapping(uint256 => bool)) stolenNfts;

    function setStolenNft(address nft, uint256 tokenId) public {
        stolenNfts[nft][tokenId] = true;
    }

    function validateTokensAreNotStolen(address tokenAddress, uint256[] calldata tokenIds, Message[] calldata proofs)
        external
        view
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (stolenNfts[tokenAddress][tokenIds[i]]) revert StolenNft();
        }
    }
}
