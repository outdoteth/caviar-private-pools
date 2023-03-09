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
        address payable pool;
        address nft;
        uint256[] tokenIds;
        uint256[] tokenWeights;
        PrivatePool.MerkleMultiProof proof;
        uint256 baseTokenAmount;
        bool isPublicPool;
    }

    struct Sell {
        address payable pool;
        address nft;
        uint256[] tokenIds;
        uint256[] tokenWeights;
        PrivatePool.MerkleMultiProof proof;
        IStolenNftOracle.Message[] stolenNftProofs;
        bool isPublicPool;
        bytes32[][] publicPoolProofs;
    }

    struct Deposit {
        address payable pool;
        address nft;
        uint256[] tokenIds;
    }

    struct Withdraw {
        address pool;
        address nft;
        uint256[] tokenIds;
        address token;
        uint256 tokenAmount;
    }

    struct Change {
        address payable pool;
        address nft;
        uint256[] inputTokenIds;
        uint256[] inputTokenWeights;
        PrivatePool.MerkleMultiProof inputProof;
        uint256[] outputTokenIds;
        uint256[] outputTokenWeights;
        PrivatePool.MerkleMultiProof outputProof;
    }

    error DeadlinePassed();
    error OutputAmountTooSmall();
    error PriceOutOfRange();

    /// @notice The royalty registry from manifold.xyz.
    IRoyaltyRegistry public immutable royaltyRegistry;

    constructor(IRoyaltyRegistry _royaltyRegistry) {
        royaltyRegistry = _royaltyRegistry;
    }

    receive() external payable {}

    /// @notice Executes a series of buy operations against public or private pools.
    /// @param buys The buy operations to execute.
    /// @param deadline The deadline for the transaction to be mined. Will revert if timestamp is greater than deadline.
    /// If it's set to 0 then there is no deadline.
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
                netInputAmount = Pair(buys[i].pool).nftBuy{value: buys[i].baseTokenAmount}(
                    buys[i].tokenIds, buys[i].baseTokenAmount, 0
                );
            } else {
                // execute the buy against a private pool
                (netInputAmount,) = PrivatePool(buys[i].pool).buy{value: buys[i].baseTokenAmount}(
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

    /// @notice Executes a series of sell operations against public or private pools.
    /// @param sells The sell operations to execute.
    /// @param minOutputAmount The minimum amount of output tokens that must be received for the transaction to succeed.
    /// @param deadline The deadline for the transaction to be mined. Will revert if timestamp is greater than deadline.
    /// Set to 0 for there to be no deadline.
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
            ERC721(sells[i].nft).setApprovalForAll(sells[i].pool, true);

            uint256 netOutputAmount;
            if (sells[i].isPublicPool) {
                // exceute the sell against a public pool
                netOutputAmount = Pair(sells[i].pool).nftSell(
                    sells[i].tokenIds,
                    0,
                    0,
                    sells[i].publicPoolProofs,
                    // ReservoirOracle.Message[] is the exact same as IStolenNftOracle.Message[] and can be
                    // decoded/encoded 1-to-1.
                    abi.decode(abi.encode(sells[i].stolenNftProofs), (ReservoirOracle.Message[]))
                );
            } else {
                // execute the sell against a private pool
                (netOutputAmount,) = PrivatePool(sells[i].pool).sell(
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

    /// @notice Executes a deposit to a private pool (transfers NFTs and ETH to the pool).
    /// @param privatePool The private pool to deposit to.
    /// @param nft The NFT contract address.
    /// @param tokenIds The token IDs of the NFTs to deposit.
    /// @param minPrice The minimum price of the pool. Will revert if price is smaller than this.
    /// @param maxPrice The maximum price of the pool. Will revert if price is greater than this.
    /// @param deadline The deadline for the transaction to be mined. Will revert if timestamp is greater than deadline.
    /// Set to 0 for deadline to be ignored.
    function deposit(
        address payable privatePool,
        address nft,
        uint256[] calldata tokenIds,
        uint256 minPrice,
        uint256 maxPrice,
        uint256 deadline
    ) public payable {
        // check deadline has not passed (if any)
        if (block.timestamp > deadline && deadline != 0) {
            revert DeadlinePassed();
        }

        // check pool price is in between min and max
        uint256 price = PrivatePool(privatePool).price();
        if (price > maxPrice || price < minPrice) {
            revert PriceOutOfRange();
        }

        // transfer NFTs from caller
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ERC721(nft).safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }

        // approve pair to transfer NFTs from router
        ERC721(nft).setApprovalForAll(privatePool, true);

        // execute deposit
        PrivatePool(privatePool).deposit{value: msg.value}(tokenIds, msg.value);
    }

    /// @notice Executes a series of change operations against a private pool.
    /// @param changes The change operations to execute.
    /// @param deadline The deadline for the transaction to be mined. Will revert if timestamp is greater than deadline.
    /// Set to 0 for deadline to be ignored.
    function change(Change[] calldata changes, uint256 deadline) public payable {
        // check deadline has not passed (if any)
        if (block.timestamp > deadline && deadline != 0) {
            revert DeadlinePassed();
        }

        // loop through and execute the changes
        for (uint256 i = 0; i < changes.length; i++) {
            Change memory _change = changes[i];

            // transfer NFTs from caller
            for (uint256 j = 0; j < changes[i].inputTokenIds.length; j++) {
                ERC721(_change.nft).safeTransferFrom(msg.sender, address(this), _change.inputTokenIds[j]);
            }

            // approve pair to transfer NFTs from router
            ERC721(_change.nft).setApprovalForAll(_change.pool, true);

            // execute change
            PrivatePool(_change.pool).change{value: msg.value}(
                _change.inputTokenIds,
                _change.inputTokenWeights,
                _change.inputProof,
                _change.outputTokenIds,
                _change.outputTokenWeights,
                _change.outputProof
            );

            // transfer NFTs to caller
            for (uint256 j = 0; j < changes[i].outputTokenIds.length; j++) {
                ERC721(_change.nft).safeTransferFrom(address(this), msg.sender, _change.outputTokenIds[j]);
            }
        }

        // refund any surplus ETH to the caller
        if (address(this).balance > 0) {
            msg.sender.safeTransferETH(address(this).balance);
        }
    }

    /// @notice Pays royalties to the royalty recipient for a given NFT and sale price. Looks up the royalty info from
    /// the manifold registry.
    /// @param tokenAddress The address of the NFT contract.
    /// @param tokenId The token ID of the NFT.
    /// @param salePrice The sale price of the NFT.
    /// @return royaltyFee The royalty fee to pay.
    /// @return recipient The address to pay the royalty fee to.
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
