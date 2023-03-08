// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

import {PrivatePool} from "./PrivatePool.sol";
import {IStolenNftOracle} from "./interfaces/IStolenNftOracle.sol";

contract EthRouter is ERC721TokenReceiver {
    struct Buy {
        address payable privatePool;
        address nft;
        uint256[] tokenIds;
        uint256[] tokenWeights;
        PrivatePool.MerkleMultiProof proof;
        uint256 baseTokenAmount;
    }

    struct Sell {
        address payable privatePool;
        address nft;
        uint256[] tokenIds;
        uint256[] tokenWeights;
        PrivatePool.MerkleMultiProof proof;
        IStolenNftOracle.Message[] stolenNftProofs;
    }

    struct Deposit {
        address privatePool;
        uint256[] tokenIds;
    }

    struct Withdraw {
        address privatePool;
        address nft;
        uint256[] tokenIds;
        address token;
        uint256 tokenAmount;
    }

    struct Change {
        address privatePool;
        uint256[] inputTokenIds;
        uint256[] inputTokenWeights;
        PrivatePool.MerkleMultiProof inputProof;
        uint256[] outputTokenIds;
        uint256[] outputTokenWeights;
        PrivatePool.MerkleMultiProof outputProof;
    }

    error InputAmountTooLarge();
    error DeadlinePassed();
    error OutputAmountTooSmall();

    /// @notice The royalty registry from manifold.xyz.
    IRoyaltyRegistry public royaltyRegistry;

    function buy(Buy[] calldata buys, uint256 deadline) public payable {
        // check that the deadline has not passed (if any)
        if (block.timestamp > deadline && deadline != 0) {
            revert DeadlinePassed();
        }

        // TODO: Add caviar buys too

        // execute the the buys
        uint256 totalInputAmount = 0;
        for (uint256 i = 0; i < buys.length; i++) {
            // execute the buy against the pool
            (uint256 netInputAmount,) = PrivatePool(buys[i].privatePool).buy{value: buys[i].baseTokenAmount}(
                buys[i].tokenIds, buys[i].tokenWeights, buys[i].proof
            );

            // add the net input amount to the total input amount
            totalInputAmount += netInputAmount;

            // transfer the tokens back to the sender
            // TODO: Gas test this, can potentially save a lot by adding a recipient parameter to the buy function
            for (uint256 j = 0; j < buys[i].tokenIds.length; j++) {
                // transfer the NFT to the caller
                ERC721(buys[i].nft).transferFrom(address(this), msg.sender, buys[i].tokenIds[j]);
            }
        }

        // TODO: add royalty fees

        // transfer any excess ETH back to the caller
        if (msg.value > totalInputAmount) {
            payable(msg.sender).transfer(msg.value - totalInputAmount);
        }
    }

    function sell(Sell[] calldata sells, uint256 minOutputAmount, uint256 deadline) public {
        // check that the deadline has not passed (if any)
        if (block.timestamp > deadline && deadline != 0) {
            revert DeadlinePassed();
        }

        // execute the the sells
        uint256 totalOutputAmount = 0;
        for (uint256 i = 0; i < sells.length; i++) {
            for (uint256 j = 0; j < sells[i].tokenIds.length; j++) {
                // transfer the NFTs from the caller
                ERC721(sells[i].nft).transferFrom(msg.sender, address(this), sells[i].tokenIds[i]);
            }

            // execute the sell against the pool
            (uint256 netOutputAmount,) = PrivatePool(sells[i].privatePool).sell(
                sells[i].tokenIds, sells[i].tokenWeights, sells[i].proof, sells[i].stolenNftProofs
            );

            // add the net output amount to the total output amount
            totalOutputAmount += netOutputAmount;
        }

        // check that the net output amount is greater than the min output amount
        if (totalOutputAmount < minOutputAmount) {
            revert OutputAmountTooSmall();
        }

        // transfer the ETH to the caller
        payable(msg.sender).transfer(totalOutputAmount);
    }

    function deposit(Deposit[] calldata deposits, uint256 minPrice, uint256 maxPrice, uint256 deadline)
        public
        payable
    {}
    function withdraw(Withdraw[] calldata withdraws, uint256 minPrice, uint256 maxPrice, uint256 deadline) public {}
    function change(Change[] calldata changes, uint256 maxFeeAmount, uint256 deadline) public payable {}
}
