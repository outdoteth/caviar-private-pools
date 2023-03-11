// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {IERC2981} from "openzeppelin/interfaces/IERC2981.sol";
import {IRoyaltyRegistry} from "royalty-registry-solidity/IRoyaltyRegistry.sol";

import {IStolenNftOracle} from "./interfaces/IStolenNftOracle.sol";

contract PrivatePool is ERC721TokenReceiver {
    using SafeTransferLib for address;

    /// @notice Merkle proof input for a sparse merkle multi proof. It can be generated with a library like:
    /// https://github.com/OpenZeppelin/merkle-tree#treegetmultiproof
    struct MerkleMultiProof {
        bytes32[] proof;
        bool[] flags;
    }

    // forgefmt: disable-next-item
    event Initialize(address indexed baseToken, address indexed nft, uint128 virtualBaseTokenReserves, uint128 virtualNftReserves, uint16 feeRate, bytes32 merkleRoot, address stolenNftOracle, bool payRoyalties);
    event Buy(uint256[] tokenIds, uint256[] tokenWeights, uint256 inputAmount, uint256 feeAmount);
    event Sell(uint256[] tokenIds, uint256[] tokenWeights, uint256 outputAmount, uint256 feeAmount);
    event Deposit(uint256[] tokenIds, uint256 baseTokenAmount);
    event Withdraw(address indexed nft, uint256[] tokenIds, address token, uint256 amount);
    // forgefmt: disable-next-item
    event Change(uint256[] inputTokenIds, uint256[] inputTokenWeights, uint256[] outputTokenIds, uint256[] outputTokenWeights, uint256 feeAmount);
    event SetVirtualReserves(uint128 virtualBaseTokenReserves, uint128 virtualNftReserves);
    event SetMerkleRoot(bytes32 merkleRoot);
    event SetFeeRate(uint16 feeRate);
    event SetStolenNftOracle(address stolenNftOracle);
    event SetPayRoyalties(bool payRoyalties);

    error AlreadyInitialized();
    error Unauthorized();
    error InvalidEthAmount();
    error InvalidMerkleProof();
    error InsufficientInputWeight();
    error FeeRateTooHigh();

    address public baseToken;
    address public nft;

    /// @notice The fee rate (in basis points) 2_000 = 2%
    uint16 public feeRate;

    /// @notice Whether or not the pool has been initialized.
    bool public initialized;

    /// @notice Whether or not the pool pays royalties to the NFT creator on each trade.
    bool public payRoyalties;

    /// @notice The virtual base token reserves used in the xy=k invariant. Changing this will change the liquidity
    /// depth and price of the pool.
    uint128 public virtualBaseTokenReserves;

    /// @notice The virtual nft reserves used in the xy=k invariant. Changing this will change the liquidity
    /// depth and price of the pool.
    /// @dev The virtual NFT reserves that a user sets. If it's desired to set the reserves to match 16 NFTs then the
    /// virtual reserves should be set to 16e18. If weights are enabled by setting the merkle root to be non-zero then
    /// the virtual reserves should be set to the sum of the weights of the NFTs; where floor NFTs all have a weight of
    /// 1e18. A rarer NFT may have a weight of 2.3e18 if it's 2.3x more valuable than a floor.
    uint128 public virtualNftReserves;

    /// @notice The merkle root of all the token weights in the pool. If the merkle root is set to bytes32(0) then all
    /// NFTs are set to have a weight of 1e18.
    bytes32 public merkleRoot;

    /// @notice The NFT oracle to check if an NFT is stolen. If it's set to be address(0) then the stolen NFT check is
    /// skipped.
    address public stolenNftOracle;

    /// @notice The factory contract that created this pool.
    address public immutable factory;

    /// @notice The royalty registry from manifold.xyz.
    address public immutable royaltyRegistry;

    modifier onlyOwner() virtual {
        if (msg.sender != ERC721(factory).ownerOf(uint160(address(this)))) {
            revert Unauthorized();
        }
        _;
    }

    receive() external payable {}

    constructor(address _factory, address _royaltyRegistry) {
        factory = _factory;
        royaltyRegistry = _royaltyRegistry;
    }

    /// @notice Initializes the private pool and sets the initial parameters. Should only be called once by the factory.
    /// @param _baseToken The address of the base token
    /// @param _nft The address of the NFT
    /// @param _virtualBaseTokenReserves The virtual base token reserves
    /// @param _virtualNftReserves The virtual NFT reserves
    /// @param _feeRate The fee rate (in basis points) 2_000 = 2%
    /// @param _merkleRoot The merkle root
    /// @param _stolenNftOracle The address of the stolen NFT oracle
    function initialize(
        address _baseToken,
        address _nft,
        uint128 _virtualBaseTokenReserves,
        uint128 _virtualNftReserves,
        uint16 _feeRate,
        bytes32 _merkleRoot,
        address _stolenNftOracle,
        bool _payRoyalties
    ) public {
        // prevent duplicate initialization
        if (initialized) revert AlreadyInitialized();

        // check that the fee rate is less than 50%
        if (_feeRate > 5_000) revert FeeRateTooHigh();

        // set the state variables
        baseToken = _baseToken;
        nft = _nft;
        virtualBaseTokenReserves = _virtualBaseTokenReserves;
        virtualNftReserves = _virtualNftReserves;
        feeRate = _feeRate;
        merkleRoot = _merkleRoot;
        stolenNftOracle = _stolenNftOracle;
        payRoyalties = _payRoyalties;

        // mark the pool as initialized
        initialized = true;

        // emit the events
        emit Initialize(
            _baseToken,
            _nft,
            _virtualBaseTokenReserves,
            _virtualNftReserves,
            _feeRate,
            _merkleRoot,
            _stolenNftOracle,
            _payRoyalties
        );
    }

    /// @notice Buys NFTs from the pool, paying with base tokens from the caller. Then transfers the bought NFTs to the
    /// caller. The net cost depends on the current price, fee rate and assigned NFT weights.
    /// @dev DO NOT call this function directly unless you know what you are doing. Instead, use a wrapper contract that
    /// will check the max input amount and revert if the slippage is too high.
    /// @param tokenIds The token IDs of the NFTs to buy.
    /// @param tokenWeights The weights of the NFTs to buy.
    /// @param proof The merkle proof for the weights of each NFT to buy.
    /// @return netInputAmount The amount of base tokens spent inclusive of fees.
    /// @return feeAmount The amount of base tokens spent on fees.
    function buy(uint256[] calldata tokenIds, uint256[] calldata tokenWeights, MerkleMultiProof calldata proof)
        public
        payable
        returns (uint256 netInputAmount, uint256 feeAmount)
    {
        // ~~~ Checks ~~~ //

        // calculate the sum of weights of the NFTs to buy
        uint256 weightSum = sumWeightsAndValidateProof(tokenIds, tokenWeights, proof);

        // calculate the required net input amount and fee amount
        (netInputAmount, feeAmount) = buyQuote(weightSum);

        // ensure the caller sent enough ETH if the base token is ETH or that the caller sent 0 ETH if the base token is
        // not ETH
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

        // calculate the sale price (assume it's the same for each NFT even if weights differ)
        uint256 salePrice = (netInputAmount - feeAmount) / tokenIds.length;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            // transfer the NFT to the caller
            ERC721(nft).safeTransferFrom(address(this), msg.sender, tokenIds[i]);

            if (payRoyalties) {
                // pay the royalty fee for the NFT
                (uint256 royaltyFee,) = _payRoyalty(nft, tokenIds[i], salePrice);

                // add the royalty fee to the net input amount
                netInputAmount += royaltyFee;
            }
        }

        // if the base token is ETH then refund any excess ETH to the caller
        if (baseToken == address(0) && msg.value > netInputAmount) {
            msg.sender.safeTransferETH(msg.value - netInputAmount);
        }

        // emit the buy event
        emit Buy(tokenIds, tokenWeights, netInputAmount, feeAmount);
    }

    /// @notice Sells NFTs into the pool and transfers base tokens to the caller. NFTs are transferred from the caller
    /// to the pool. The net sale amount depends on the current price, fee rate and assigned NFT weights.
    /// @dev DO NOT call this function directly unless you know what you are doing. Instead, use a wrapper contract that
    /// will check the min output amount and revert if the slippage is too high.
    /// @param tokenIds The token IDs of the NFTs to sell.
    /// @param tokenWeights The weights of the NFTs to sell.
    /// @param proof The merkle proof for the weights of each NFT to sell.
    /// @param stolenNftProofs The proofs that show each NFT is not stolen.
    /// @return netOutputAmount The amount of base tokens received inclusive of fees.
    /// @return feeAmount The amount of base tokens to pay in fees.
    function sell(
        uint256[] calldata tokenIds,
        uint256[] calldata tokenWeights,
        MerkleMultiProof calldata proof,
        IStolenNftOracle.Message[] calldata stolenNftProofs
    ) public returns (uint256 netOutputAmount, uint256 feeAmount) {
        // ~~~ Checks ~~~ //

        // calculate the sum of weights of the NFTs to sell
        uint256 weightSum = sumWeightsAndValidateProof(tokenIds, tokenWeights, proof);

        // calculate the net output amount and fee amount
        (netOutputAmount, feeAmount) = sellQuote(weightSum);

        //  check the nfts are not stolen
        if (stolenNftOracle != address(0)) {
            IStolenNftOracle(stolenNftOracle).validateTokensAreNotStolen(nft, tokenIds, stolenNftProofs);
        }

        // ~~~ Effects ~~~ //

        // update the virtual reserves
        virtualBaseTokenReserves -= uint128(netOutputAmount - feeAmount);
        virtualNftReserves += uint128(weightSum);

        // ~~~ Interactions ~~~ //

        // calculate the sale price (assume it's the same for each NFT even if weights differ)
        uint256 salePrice = (netOutputAmount + feeAmount) / tokenIds.length;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            // transfer each nft from the caller
            ERC721(nft).safeTransferFrom(msg.sender, address(this), tokenIds[i]);

            if (payRoyalties) {
                // pay the royalty fee for the NFT
                (uint256 royaltyFee,) = _payRoyalty(nft, tokenIds[i], salePrice);

                // subtract the royalty fee from the net output amount
                netOutputAmount -= royaltyFee;
            }
        }

        // transfer eth to the caller if the base token is ETH or transfer the base token to the caller if the base
        // token is not ETH
        if (baseToken == address(0)) {
            msg.sender.safeTransferETH(netOutputAmount);
        } else {
            ERC20(baseToken).transfer(msg.sender, netOutputAmount);
        }

        // emit the sell event
        emit Sell(tokenIds, tokenWeights, netOutputAmount, feeAmount);
    }

    /// @notice Deposits base tokens and NFTs into the pool. The caller must approve the pool to transfer their NFTs and
    /// base tokens.
    /// @dev DO NOT call this function directly unless you know what you are doing. Instead, use a wrapper contract that
    /// will check the current price is within the desired bounds.
    /// @param tokenIds The token IDs of the NFTs to deposit.
    /// @param baseTokenAmount The amount of base tokens to deposit.
    function deposit(uint256[] calldata tokenIds, uint256 baseTokenAmount) public payable {
        // ~~~ Checks ~~~ //

        // ensure the caller sent a valid amount of ETH if base token is ETH or that the caller sent 0 ETH if base token
        // is not ETH
        if ((baseToken == address(0) && msg.value != baseTokenAmount) || (msg.value > 0 && baseToken != address(0))) {
            revert InvalidEthAmount();
        }

        // ~~~ Interactions ~~~ //

        // transfer the nfts from the caller
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ERC721(nft).safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }

        if (baseToken != address(0)) {
            // transfer the base tokens from the caller
            ERC20(baseToken).transferFrom(msg.sender, address(this), baseTokenAmount);
        }

        // emit the deposit event
        emit Deposit(tokenIds, baseTokenAmount);
    }

    /// @notice Withdraws NFTs and tokens from the pool. Can only be called by the owner of the pool.
    /// @param _nft The address of the NFT.
    /// @param tokenIds The token IDs of the NFTs to withdraw.
    /// @param token The address of the token to withdraw.
    /// @param tokenAmount The amount of tokens to withdraw.
    function withdraw(address _nft, uint256[] calldata tokenIds, address token, uint256 tokenAmount) public onlyOwner {
        // ~~~ Interactions ~~~ //

        // transfer the nfts to the caller
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ERC721(_nft).safeTransferFrom(address(this), msg.sender, tokenIds[i]);
        }

        if (token == address(0)) {
            // transfer the ETH to the caller
            msg.sender.safeTransferETH(tokenAmount);
        } else {
            // transfer the tokens to the caller
            ERC20(token).transfer(msg.sender, tokenAmount);
        }

        // emit the withdraw event
        emit Withdraw(_nft, tokenIds, token, tokenAmount);
    }

    /// @notice Changes a set of NFTs that the caller owns for another set of NFTs in the pool. The caller must approve
    /// the pool to transfer the NFTs. The sum of the caller's NFT weights must be less than or equal to the sum of the
    /// output pool NFTs weights. The caller must also pay a fee depending on the current price and net input weight.
    /// @dev   DO NOT call this function directly unless you are sure. The price can be manipulated to increase the fee.
    /// Instead, use a wrapper contract to validate the max fee amount and revert if the fee is too large.
    /// @param inputTokenIds The token IDs of the NFTs to change.
    /// @param inputTokenWeights The weights of the NFTs to change.
    /// @param inputProof The merkle proof for the weights of each NFT to change.
    /// @param outputTokenIds The token IDs of the NFTs to receive.
    /// @param outputTokenWeights The weights of the NFTs to receive.
    /// @param outputProof The merkle proof for the weights of each NFT to receive.
    function change(
        uint256[] calldata inputTokenIds,
        uint256[] calldata inputTokenWeights,
        MerkleMultiProof calldata inputProof,
        uint256[] calldata outputTokenIds,
        uint256[] calldata outputTokenWeights,
        MerkleMultiProof calldata outputProof
    ) public payable returns (uint256 feeAmount) {
        // ~~~ Checks ~~~ //

        // fix stack too deep
        {
            // calculate the sum of weights for the input nfts
            uint256 inputWeightSum = sumWeightsAndValidateProof(inputTokenIds, inputTokenWeights, inputProof);

            // calculate the sum of weights for the output nfts
            uint256 outputWeightSum = sumWeightsAndValidateProof(outputTokenIds, outputTokenWeights, outputProof);

            // check that the input weights are greater than or equal to the output weights
            if (inputWeightSum < outputWeightSum) revert InsufficientInputWeight();

            // calculate the fee amount
            feeAmount = changeFeeQuote(inputWeightSum);
        }

        // ~~~ Interactions ~~~ //

        // check caller sent enough ETH if base token is ETH or that the caller sent 0 ETH if base token is not ETH
        if ((baseToken == address(0) && msg.value < feeAmount) || (baseToken != address(0) && msg.value > 0)) {
            revert InvalidEthAmount();
        }

        if (baseToken != address(0)) {
            // transfer the fee amount of base tokens from the caller
            ERC20(baseToken).transferFrom(msg.sender, address(this), feeAmount);
        }

        // transfer the input nfts from the caller
        for (uint256 i = 0; i < inputTokenIds.length; i++) {
            ERC721(nft).safeTransferFrom(msg.sender, address(this), inputTokenIds[i]);
        }

        // transfer the output nfts to the caller
        for (uint256 i = 0; i < outputTokenIds.length; i++) {
            ERC721(nft).safeTransferFrom(address(this), msg.sender, outputTokenIds[i]);
        }

        // if the base token is ETH then refund any excess ETH to the caller
        if (baseToken == address(0) && msg.value > feeAmount) {
            msg.sender.safeTransferETH(msg.value - feeAmount);
        }

        // emit the change event
        emit Change(inputTokenIds, inputTokenWeights, outputTokenIds, outputTokenWeights, feeAmount);
    }

    /// @notice Executes a transaction from the pool account to a target contract. The caller must be the owner of the
    /// pool. This allows for use cases such as claiming airdrops.
    /// @param target The address of the target contract.
    /// @param data The data to send to the target contract.
    /// @return returnData The return data of the transaction.
    function execute(address target, bytes memory data) public payable onlyOwner returns (bytes memory) {
        // call the target with the value and data
        (bool success, bytes memory returnData) = target.call{value: msg.value}(data);

        // if the call succeeded return the return data
        if (success) return returnData;

        // if we got an error bubble up the error message
        if (returnData.length > 0) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let returnData_size := mload(returnData)
                revert(add(32, returnData), returnData_size)
            }
        } else {
            revert();
        }
    }

    /// @notice Sets the virtual base token reserves and virtual NFT reserves. Can only be called by the owner of the
    /// pool. These parameters affect the price and liquidity depth of the pool.
    /// @param newVirtualBaseTokenReserves The new virtual base token reserves.
    /// @param newVirtualNftReserves The new virtual NFT reserves.
    function setVirtualReserves(uint128 newVirtualBaseTokenReserves, uint128 newVirtualNftReserves) public onlyOwner {
        // set the virtual base token reserves and virtual nft reserves
        virtualBaseTokenReserves = newVirtualBaseTokenReserves;
        virtualNftReserves = newVirtualNftReserves;

        // emit the set virtual reserves event
        emit SetVirtualReserves(newVirtualBaseTokenReserves, newVirtualNftReserves);
    }

    /// @notice Sets the merkle root. Can only be called by the owner of the pool. The merkle root is used to validate
    /// the NFT weights.
    /// @param newMerkleRoot The new merkle root.
    function setMerkleRoot(bytes32 newMerkleRoot) public onlyOwner {
        // set the merkle root
        merkleRoot = newMerkleRoot;

        // emit the set merkle root event
        emit SetMerkleRoot(newMerkleRoot);
    }

    /// @notice Sets the fee rate. Can only be called by the owner of the pool. The fee rate is used to calculate the
    /// fee amount when swapping or changing NFTs. The fee rate is in basis points (1/100th of a percent). For example,
    /// 10_000 == 100%, 200 == 2%, 1 == 0.01%.
    /// @param newFeeRate The new fee rate (in basis points)
    function setFeeRate(uint16 newFeeRate) public onlyOwner {
        // check that the fee rate is less than 50%
        if (newFeeRate > 5_000) revert FeeRateTooHigh();

        // set the fee rate
        feeRate = newFeeRate;

        // emit the set fee rate event
        emit SetFeeRate(newFeeRate);
    }

    /// @notice Sets the stolen NFT oracle. Can only be called by the owner of the pool. The stolen NFT oracle is used
    /// to check if an NFT is stolen. If it's set to the zero address then no stolen NFT checks are performed.
    /// @param newStolenNftOracle The new stolen NFT oracle.
    function setStolenNftOracle(address newStolenNftOracle) public onlyOwner {
        // set the stolen NFT oracle
        stolenNftOracle = newStolenNftOracle;

        // emit the set stolen NFT oracle event
        emit SetStolenNftOracle(newStolenNftOracle);
    }

    /// @notice Sets the pay royalties flag. Can only be called by the owner of the pool. If royalties are enabled then
    /// the pool will pay royalties when buying or selling NFTs.
    /// @param newPayRoyalties The new pay royalties flag.
    function setPayRoyalties(bool newPayRoyalties) public onlyOwner {
        // set the pay royalties flag
        payRoyalties = newPayRoyalties;

        // emit the set pay royalties event
        emit SetPayRoyalties(newPayRoyalties);
    }

    /// @notice Returns the required input of buying a given amount of NFTs inclusive of the fee which is dependent on
    /// the currently set fee rate.
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

    /// @notice Returns the output amount of selling a given amount of NFTs inclusive of the fee which is dependent on
    /// the currently set fee rate.
    /// @param inputAmount The amount of NFTs to sell multiplied by 1e18.
    /// @return netOutputAmount The output amount of base tokens inclusive of the fee.
    /// @return feeAmount The fee amount.
    function sellQuote(uint256 inputAmount) public view returns (uint256 netOutputAmount, uint256 feeAmount) {
        // calculate the output amount based on xy=k invariant
        uint256 outputAmount = inputAmount * virtualBaseTokenReserves / (virtualNftReserves + inputAmount);

        feeAmount = outputAmount * feeRate / 10_000;
        netOutputAmount = outputAmount - feeAmount;
    }

    /// @notice Returns the fee required to change a given amount of NFTs. The fee is based on the current price in the
    /// pool and the currently set fee rate.
    /// @param inputAmount The amount of NFTs to change multiplied by 1e18.
    /// @return feeAmount The fee amount.
    function changeFeeQuote(uint256 inputAmount) public view returns (uint256 feeAmount) {
        feeAmount = (virtualBaseTokenReserves * inputAmount * feeRate) / (10_000 * virtualNftReserves);
    }

    /// @notice Returns the price of the pool to 18 decimals of accuracy.
    /// @return price The price of the pool.
    function price() public view returns (uint256) {
        // ensure that the exponent is always to 18 decimals of accuracy
        uint256 exponent = baseToken == address(0) ? 18 : (36 - ERC20(baseToken).decimals());
        return (virtualBaseTokenReserves * 10 ** exponent) / virtualNftReserves;
    }

    /// @notice Sums the weights of each NFT and validates that the weights are correct by verifying the merkle proof.
    /// @param tokenIds The token IDs of the NFTs to sum the weights for.
    /// @param tokenWeights The weights of each NFT in the token IDs array.
    /// @param proof The merkle proof for the weights of each NFT.
    /// @return sum The sum of the weights of each NFT.
    function sumWeightsAndValidateProof(
        uint256[] calldata tokenIds,
        uint256[] calldata tokenWeights,
        MerkleMultiProof calldata proof
    ) public view returns (uint256) {
        // if the merkle root is not set then set the weight of each nft to be 1e18
        if (merkleRoot == bytes32(0)) {
            return tokenIds.length * 1e18;
        }

        uint256 sum;
        bytes32[] memory leafs = new bytes32[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // create the leaf for the merkle proof
            leafs[i] = keccak256(bytes.concat(keccak256(abi.encode(tokenIds[i], tokenWeights[i]))));

            // sum each token weight
            sum += tokenWeights[i];
        }

        // validate that the weights are valid against the merkle proof
        if (!MerkleProofLib.verifyMultiProof(proof.proof, merkleRoot, leafs, proof.flags)) {
            revert InvalidMerkleProof();
        }

        return sum;
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
        address lookupAddress = IRoyaltyRegistry(royaltyRegistry).getRoyaltyLookupAddress(tokenAddress);

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
