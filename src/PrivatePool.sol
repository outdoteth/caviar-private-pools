// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";

import {IStolenNftOracle} from "./interfaces/IStolenNftOracle.sol";

contract PrivatePool is ERC721TokenReceiver {
    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event Initialize(
        address indexed baseToken,
        address indexed nft,
        uint128 virtualBaseTokenReserves,
        uint128 virtualNftReserves,
        uint16 feeRate,
        bytes32 merkleRoot,
        address stolenNftOracle
    );
    event Buy(
        uint256[] indexed tokenIds, uint256[] indexed tokenWeights, uint256 indexed inputAmount, uint256 feeAmount
    );
    event Sell(
        uint256[] indexed tokenIds, uint256[] indexed tokenWeights, uint256 indexed outputAmount, uint256 feeAmount
    );

    error AlreadyInitialized();
    error Unauthorized();
    error InvalidEthAmount();
    error InvalidMerkleProof();

    address public baseToken;
    address public nft;
    uint16 public feeRate;
    bool public initialized;
    uint128 public virtualBaseTokenReserves;

    /// @dev The virtual NFT reserves that a user sets. If it's desired to set the
    ///      reserves to match 16 NFTs then the virtual reserves should be set to 16e18.
    ///      If weights are enabled by setting the merkle root to be non-zero then the
    ///      virtual reserves should be set to the sum of the weights of the NFTs; where
    ///      floor NFTs all have a weight of 1. A rarer NFT may have a weight of 2.3 if
    ///      it's 2.3x more valuable than a floor.
    uint128 public virtualNftReserves;
    bytes32 public merkleRoot;
    address public stolenNftOracle;
    address public owner;

    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /// @notice Initializes the private pool and sets the initial parameters.
    ///         Should only be called once by the factory.
    /// @param _baseToken The address of the base token
    /// @param _nft The address of the NFT
    /// @param _virtualBaseTokenReserves The virtual base token reserves
    /// @param _virtualNftReserves The virtual NFT reserves
    /// @param _feeRate The fee rate (in basis points) 2_000 = 2%
    /// @param _merkleRoot The merkle root
    /// @param _stolenNftOracle The address of the stolen NFT oracle
    /// @param _owner The address of the owner
    function initialize(
        address _baseToken,
        address _nft,
        uint128 _virtualBaseTokenReserves,
        uint128 _virtualNftReserves,
        uint16 _feeRate,
        bytes32 _merkleRoot,
        address _stolenNftOracle,
        address _owner
    ) public {
        // prevent duplicate initialization
        if (initialized) revert AlreadyInitialized();

        // set the state variables
        baseToken = _baseToken;
        nft = _nft;
        virtualBaseTokenReserves = _virtualBaseTokenReserves;
        virtualNftReserves = _virtualNftReserves;
        feeRate = _feeRate;
        merkleRoot = _merkleRoot;
        stolenNftOracle = _stolenNftOracle;
        owner = _owner;

        // mark the pool as initialized
        initialized = true;

        // emit the events
        emit OwnershipTransferred(address(0), _owner);
        emit Initialize(
            _baseToken, _nft, _virtualBaseTokenReserves, _virtualNftReserves, _feeRate, _merkleRoot, _stolenNftOracle
        );
    }

    /// @notice Buys NFTs from the pool, paying with base tokens from the caller.
    ///         Then transfers the bought NFTs to the caller. The net cost depends
    ///         on the current price, fee rate and assigned NFT weights.
    /// @param tokenIds The token IDs of the NFTs to buy.
    /// @param tokenWeights The weights of the NFTs to buy.
    /// @param proofs The merkle proof for the weights of each NFT to buy.
    /// @return netInputAmount The amount of base tokens spent inclusive of fees.
    /// @return feeAmount The amount of base tokens spent on fees.
    function buy(uint256[] calldata tokenIds, uint256[] calldata tokenWeights, bytes32[][] calldata proofs)
        public
        payable
        returns (uint256 netInputAmount, uint256 feeAmount)
    {
        // ~~~ Checks ~~~ //

        // calculate the sum of weights of the NFTs to buy
        uint256 weightSum = sumWeightsAndValidateProof(tokenIds, tokenWeights, proofs);

        // calculate the required net input amount and fee amount
        (netInputAmount, feeAmount) = buyQuote(weightSum);

        // ensure the caller sent enough ETH if the base token is ETH
        // or that the caller sent 0 ETH if the base token is not ETH
        if ((msg.value < netInputAmount && baseToken == address(0)) || (baseToken != address(0) && msg.value > 0)) {
            revert InvalidEthAmount();
        }

        // ~~~ Effects ~~~ //

        // update the virtual reserves
        virtualBaseTokenReserves += uint128(netInputAmount - feeAmount);
        virtualNftReserves -= uint128(weightSum);

        // ~~~ Interactions ~~~ //

        // transfer the base token from the caller if base token is not ETH
        if (baseToken != address(0)) {
            ERC20(baseToken).transferFrom(msg.sender, address(this), netInputAmount);
        }

        // transfer the NFTs to the caller
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ERC721(nft).safeTransferFrom(address(this), msg.sender, tokenIds[i]);
        }

        // if the base token is ETH then refund any excess ETH to the caller
        if (baseToken == address(0) && msg.value > netInputAmount) {
            payable(msg.sender).transfer(msg.value - netInputAmount);
        }

        // emit the buy event
        emit Buy(tokenIds, tokenWeights, netInputAmount, feeAmount);
    }

    /// @notice Sells NFTs into the pool and transfers base tokens to the caller. NFTs
    ///         are transferred from the caller to the pool. The net proceeds depend on
    ///         the current price, fee rate and assigned NFT weights.
    /// @param tokenIds The token IDs of the NFTs to sell.
    /// @param tokenWeights The weights of the NFTs to sell.
    /// @param proofs The merkle proof for the weights of each NFT to sell.
    /// @param stolenNftProofs The proofs that show each NFT is not stolen.
    /// @return netOutputAmount The amount of base tokens received inclusive of fees.
    /// @return feeAmount The amount of base tokens to pay in fees.
    function sell(
        uint256[] calldata tokenIds,
        uint256[] calldata tokenWeights,
        bytes32[][] calldata proofs,
        IStolenNftOracle.Message[] calldata stolenNftProofs
    ) public returns (uint256 netOutputAmount, uint256 feeAmount) {
        // calculate the sum of weights of the NFTs to sell
        uint256 weightSum = sumWeightsAndValidateProof(tokenIds, tokenWeights, proofs);

        // calculate the net output amount and fee amount
        (netOutputAmount, feeAmount) = sellQuote(weightSum);

        // update the virtual reserves
        virtualBaseTokenReserves -= uint128(netOutputAmount - feeAmount);
        virtualNftReserves += uint128(weightSum);

        //  check the nfts are not stolen
        if (stolenNftOracle != address(0)) {
            IStolenNftOracle(stolenNftOracle).validateTokensAreNotStolen(nft, tokenIds, stolenNftProofs);
        }

        // transfer the nfts from the caller
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ERC721(nft).safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }

        // transfer eth to the caller if the base token is ETH or transfer
        // the base token to the caller if the base token is not ETH
        if (baseToken == address(0)) {
            payable(msg.sender).transfer(netOutputAmount);
        } else {
            ERC20(baseToken).transfer(msg.sender, netOutputAmount);
        }

        // emit the sell event
        emit Sell(tokenIds, tokenWeights, netOutputAmount, feeAmount);
    }

    /// @notice Deposits base tokens and NFTs into the pool. The caller must approve
    ///         the pool to transfer the NFTs and base tokens.
    /// @param tokenIds The token IDs of the NFTs to deposit.
    /// @param baseTokenAmount The amount of base tokens to deposit.
    function deposit(uint256[] calldata tokenIds, uint256 baseTokenAmount) public payable {}

    /// @notice Withdraws NFTs from the pool. Can only be called by the owner of the pool.
    /// @param token The address of the NFT.
    /// @param tokenIds The token IDs of the NFTs to withdraw.
    function withdrawNfts(address token, uint256[] calldata tokenIds) public onlyOwner {}

    /// @notice Withdraws tokens from the pool. Can only be called by the owner of the pool.
    /// @param token The address of the token.
    /// @param amount The amount of tokens to withdraw.
    function withdrawTokens(address token, uint256 amount) public onlyOwner {}

    /// @notice Changes a set of NFTs that the caller owns for another set of NFTs in the pool.
    ///         The caller must approve the pool to transfer the NFTs. The sum of the caller's
    ///         NFT weights must be less than or equal to the sum of the output pool NFTs weights.
    /// @param inputTokenIds The token IDs of the NFTs to change.
    /// @param inputTokenWeights The weights of the NFTs to change.
    /// @param inputProof The merkle proof for the weights of each NFT to change.
    /// @param outputTokenIds The token IDs of the NFTs to receive.
    /// @param outputTokenWeights The weights of the NFTs to receive.
    /// @param outputProof The merkle proof for the weights of each NFT to receive.
    function change(
        uint256[] calldata inputTokenIds,
        uint256[] calldata inputTokenWeights,
        bytes32[][] calldata inputProof,
        uint256[] memory outputTokenIds,
        uint256[] calldata outputTokenWeights,
        bytes32[][] calldata outputProof
    ) public {}

    /// @notice Executes a transaction from the pool account to a target contrat. The caller
    ///         must be the owner of the pool. This allows for use cases such as claiming airdrops.
    /// @param target The address of the target contract.
    /// @param value The amount of base tokens to send.
    /// @param data The data to send to the target contract.
    function execute(address target, uint256 value, bytes[] memory data) public payable onlyOwner {}

    /// @notice Sets the virtual base token reserves and virtual NFT reserves. Can only be called
    ///         by the owner of the pool.
    /// @param newVirtualBaseTokenReserves The new virtual base token reserves.
    /// @param newVirtualNftReserves The new virtual NFT reserves.
    function setVirtualReserves(uint256 newVirtualBaseTokenReserves, uint256 newVirtualNftReserves) public onlyOwner {}

    /// @notice Sets the merkle root. Can only be called by the owner of the pool.
    /// @param newMerkleRoot The new merkle root.
    function setMerkleRoot(bytes32 newMerkleRoot) public onlyOwner {}

    /// @notice Sets the fee rate. Can only be called by the owner of the pool.
    /// @param newFeeRate The new fee rate (in basis points) 2_000 = 2%
    function setFeeRate(uint16 newFeeRate) public {}

    /// @notice Sets the stolen NFT oracle. Can only be called by the owner of the pool.
    /// @param newStolenNftOracle The new stolen NFT oracle.
    function setStolenNftOracle(address newStolenNftOracle) public {}

    /// @notice Transfers ownership of the pool to a new owner.
    /// @param newOwner The address of the new owner.
    function transferOwnership(address newOwner) public virtual onlyOwner {
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }

    /// @notice Returns the required input of buying a given amount of NFTs (in 1e18) inclusive of
    ///         the fee which is dependent on the currently set fee rate.
    /// @param outputAmount The amount of NFTs to buy multiplied by 1e18.
    /// @return netInputAmount The required input amount of base tokens inclusive of the fee.
    /// @return feeAmount The fee amount.
    function buyQuote(uint256 outputAmount) public view returns (uint256 netInputAmount, uint256 feeAmount) {
        // calculate the input amount based on xy=k invariant and round up by 1 wei
        uint256 inputAmount =
            FixedPointMathLib.mulDivUp(outputAmount, virtualBaseTokenReserves, (virtualNftReserves - outputAmount));

        feeAmount = inputAmount * feeRate / 10_000;
        netInputAmount = inputAmount + feeAmount;
    }

    function sellQuote(uint256 inputAmount) public view returns (uint256 netOutputAmount, uint256 feeAmount) {
        // calculate the output amount based on xy=k invariant
        uint256 outputAmount = inputAmount * (virtualNftReserves + inputAmount) / virtualBaseTokenReserves;

        feeAmount = outputAmount * feeRate / 10_000;
        netOutputAmount = inputAmount - feeAmount;
    }

    /// @notice Sums the weights of each NFT and validates that the weights are correct
    ///         by verifying the merkle proof.
    /// @param tokenIds The token IDs of the NFTs to sum the weights for.
    /// @param tokenWeights The weights of each NFT in the token IDs array.
    /// @param proof The merkle proof for the weights of each NFT.
    /// @return sum The sum of the weights of each NFT.
    function sumWeightsAndValidateProof(
        uint256[] calldata tokenIds,
        uint256[] calldata tokenWeights,
        bytes32[][] calldata proof
    ) public view returns (uint256) {
        // if the merkle root is not set then set the weight of each nft to be 1e18
        if (merkleRoot == bytes32(0)) {
            return tokenIds.length * 1e18;
        }

        uint256 sum;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // sum each token weight
            sum += tokenWeights[i];

            // validate that the weight is valid against the merkle proof
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(tokenIds[i], tokenWeights[i]))));
            if (!MerkleProofLib.verify(proof[i], merkleRoot, leaf)) revert InvalidMerkleProof();
        }

        return sum;
    }
}
