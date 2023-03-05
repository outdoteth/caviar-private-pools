// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract PrivatePool {
    struct MerkleMultiProof {
        bytes32[] proof;
        bool[] flags;
    }

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

    error AlreadyInitialized();
    error Unauthorized();

    address public baseToken;
    address public nft;
    uint16 public feeRate;
    bool public initialized;
    uint128 public virtualBaseTokenReserves;
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
    /// @param proof The merkle proof for the weights of each NFT to buy.
    function buy(uint256[] calldata tokenIds, uint256[] calldata tokenWeights, MerkleMultiProof calldata proof)
        public
        payable
    {}

    /// @notice Sells NFTs into the pool and transfers base tokens to the caller. NFTs
    ///         are transferred from the caller to the pool. The net proceeds depend on
    ///         the current price, fee rate and assigned NFT weights.
    /// @param tokenIds The token IDs of the NFTs to sell.
    /// @param tokenWeights The weights of the NFTs to sell.
    /// @param proof The merkle proof for the weights of each NFT to sell.
    function sell(uint256[] calldata tokenIds, uint256[] calldata tokenWeights, MerkleMultiProof calldata proof)
        public
    {}

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
        MerkleMultiProof calldata inputProof,
        uint256[] memory outputTokenIds,
        uint256[] calldata outputTokenWeights,
        MerkleMultiProof calldata outputProof
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
}
