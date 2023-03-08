// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IRoyaltyRegistry} from "royalty-registry-solidity/IRoyaltyRegistry.sol";
import {IERC2981} from "openzeppelin/interfaces/IERC2981.sol";
import {Pair, ReservoirOracle} from "caviar/Pair.sol";

import {PrivatePool} from "./PrivatePool.sol";
import {IStolenNftOracle} from "./interfaces/IStolenNftOracle.sol";

contract EthRouter is ERC721TokenReceiver {
    using SafeTransferLib for address;

    struct Buy {
        address payable privatePool;
        address nft;
        uint256[] tokenIds;
        uint256[] tokenWeights;
        PrivatePool.MerkleMultiProof proof;
        uint256 baseTokenAmount;
        bool isPublicPool;
    }

    struct Sell {
        address payable privatePool;
        address nft;
        uint256[] tokenIds;
        uint256[] tokenWeights;
        PrivatePool.MerkleMultiProof proof;
        IStolenNftOracle.Message[] stolenNftProofs;
        bool isPublicPool;
        bytes32[][] publicPoolProofs;
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

    error DeadlinePassed();
    error OutputAmountTooSmall();

    /// @notice The royalty registry from manifold.xyz.
    IRoyaltyRegistry public immutable royaltyRegistry;

    constructor(IRoyaltyRegistry _royaltyRegistry) {
        royaltyRegistry = _royaltyRegistry;
    }

    receive() external payable {}

    function buy(Buy[] calldata buys, uint256 deadline) public payable {
        // check that the deadline has not passed (if any)
        if (block.timestamp > deadline && deadline != 0) {
            revert DeadlinePassed();
        }

        // loop through and execute the the buys
        for (uint256 i = 0; i < buys.length; i++) {
            uint256 netInputAmount;
            if (buys[i].isPublicPool) {
                // execute the buy against a public pool
                netInputAmount = Pair(buys[i].privatePool).nftBuy{value: buys[i].baseTokenAmount}(
                    buys[i].tokenIds, buys[i].baseTokenAmount, 0
                );
            } else {
                // execute the buy against a private pool
                (netInputAmount,) = PrivatePool(buys[i].privatePool).buy{value: buys[i].baseTokenAmount}(
                    buys[i].tokenIds, buys[i].tokenWeights, buys[i].proof
                );
            }

            // calculate the sale price of each NFT
            uint256 salePrice = netInputAmount / buys[i].tokenIds.length;

            for (uint256 j = 0; j < buys[i].tokenIds.length; j++) {
                // transfer the NFT to the caller
                ERC721(buys[i].nft).safeTransferFrom(address(this), msg.sender, buys[i].tokenIds[j]);

                // pay the royalty fee for the NFT
                _payRoyalty(buys[i].nft, buys[i].tokenIds[j], salePrice);
            }
        }

        // refund any surplus ETH to the caller
        if (address(this).balance > 0) {
            msg.sender.safeTransferETH(address(this).balance);
        }
    }

    function sell(Sell[] calldata sells, uint256 minOutputAmount, uint256 deadline) public {
        // check that the deadline has not passed (if any)
        if (block.timestamp > deadline && deadline != 0) {
            revert DeadlinePassed();
        }

        // loop through and execute the sells
        for (uint256 i = 0; i < sells.length; i++) {
            // transfer the NFTs into the router from the caller
            for (uint256 j = 0; j < sells[i].tokenIds.length; j++) {
                ERC721(sells[i].nft).safeTransferFrom(msg.sender, address(this), sells[i].tokenIds[j]);
            }

            // approve the pair to transfer NFTs from the router
            ERC721(sells[i].nft).setApprovalForAll(sells[i].privatePool, true);

            uint256 netOutputAmount;
            if (sells[i].isPublicPool) {
                // exceute the sell against a public pool
                netOutputAmount = Pair(sells[i].privatePool).nftSell(
                    sells[i].tokenIds,
                    0,
                    0,
                    sells[i].publicPoolProofs,
                    abi.decode(abi.encode(sells[i].stolenNftProofs), (ReservoirOracle.Message[]))
                );
            } else {
                // execute the sell against a private pool
                (netOutputAmount,) = PrivatePool(sells[i].privatePool).sell(
                    sells[i].tokenIds, sells[i].tokenWeights, sells[i].proof, sells[i].stolenNftProofs
                );
            }

            // pay the royalty fees for each NFT
            uint256 salePrice = netOutputAmount / sells[i].tokenIds.length;
            for (uint256 j = 0; j < sells[i].tokenIds.length; j++) {
                _payRoyalty(sells[i].nft, sells[i].tokenIds[j], salePrice);
            }
        }

        // check that the output amount is greater than the minimum
        if (address(this).balance < minOutputAmount) {
            revert OutputAmountTooSmall();
        }

        // transfer the output amount to the caller
        msg.sender.safeTransferETH(address(this).balance);
    }

    function deposit(Deposit calldata _deposit, uint256 minPrice, uint256 maxPrice, uint256 deadline) public payable {}
    function change(Change[] calldata changes, uint256 maxFeeAmount, uint256 deadline) public payable {}

    function _payRoyalty(address tokenAddress, uint256 tokenId, uint256 salePrice)
        internal
        returns (uint256 royaltyFee, address recipient)
    {
        // get the royalty lookup address
        address lookupAddress = royaltyRegistry.getRoyaltyLookupAddress(tokenAddress);

        if (IERC2981(lookupAddress).supportsInterface(type(IERC2981).interfaceId)) {
            // get the royalty fee from the registry
            (recipient, royaltyFee) = IERC2981(lookupAddress).royaltyInfo(tokenId, salePrice);

            // transfer the royalty fee to the recipient if it's greater than 0
            if (royaltyFee > 0 && recipient != address(0)) {
                recipient.safeTransferETH(royaltyFee);
            }
        }
    }
}
