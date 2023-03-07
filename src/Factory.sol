// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LibClone} from "solady/utils/LibClone.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {PrivatePool} from "./PrivatePool.sol";

contract Factory {
    using LibClone for address;

    event Create(address indexed privatePool, uint256[] indexed tokenIds, uint256 indexed baseTokenAmount);

    address public immutable privatePoolImplementation;

    constructor(address _privatePoolImplementation) {
        privatePoolImplementation = _privatePoolImplementation;
    }

    function create(
        address _baseToken,
        address _nft,
        uint128 _virtualBaseTokenReserves,
        uint128 _virtualNftReserves,
        uint16 _feeRate,
        bytes32 _merkleRoot,
        address _stolenNftOracle,
        bytes32 _salt,
        uint256[] calldata tokenIds,
        uint256 baseTokenAmount
    ) public payable returns (PrivatePool privatePool) {
        // check that the msg.value is equal to the base token amount if the base token is ETH
        // or the msg.value is equal to zero if the base token is not ETH
        if ((_baseToken == address(0) && msg.value != baseTokenAmount) || (_baseToken != address(0) && msg.value > 0)) {
            revert PrivatePool.InvalidEthAmount();
        }

        // deploy a minimal proxy clone of the private pool implementation
        privatePool = PrivatePool(payable(privatePoolImplementation.cloneDeterministic(_salt)));

        // initialize the pool
        privatePool.initialize(
            _baseToken,
            _nft,
            _virtualBaseTokenReserves,
            _virtualNftReserves,
            _feeRate,
            _merkleRoot,
            _stolenNftOracle,
            msg.sender // set the owner to be the caller
        );

        if (_baseToken == address(0)) {
            // transfer eth into the pool if base token is ETH
            payable(address(privatePool)).transfer(baseTokenAmount);
        } else {
            // deposit the base tokens from the caller into the pool
            ERC20(_baseToken).transferFrom(msg.sender, address(privatePool), baseTokenAmount);
        }

        // deposit the nfts from the caller into the pool
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ERC721(_nft).safeTransferFrom(msg.sender, address(privatePool), tokenIds[i]);
        }

        // emit create event
        emit Create(address(privatePool), tokenIds, baseTokenAmount);
    }

    function predictDeterministicAddress(address implementation, bytes32 salt, address deployer)
        public
        view
        returns (address)
    {
        return LibClone.predictDeterministicAddress(implementation, salt, deployer);
    }
}
