// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin/interfaces/IERC3156.sol";

import "../../src/PrivatePool.sol";

contract FlashBorrower is IERC3156FlashBorrower {
    PrivatePool public lender;

    constructor(PrivatePool lender_) {
        lender = lender_;
    }

    function initiateFlashLoan(address token, uint256 tokenId, bytes calldata data) public {
        if (lender.flashFeeToken() == address(0)) {
            uint256 flashFee = lender.flashFee(token, tokenId);
            lender.flashLoan{value: flashFee}(this, token, tokenId, data);
        } else {
            lender.flashLoan(this, token, tokenId, data);
        }
    }

    function onFlashLoan(address initiator, address token, uint256, uint256 fee, bytes calldata)
        public
        override
        returns (bytes32)
    {
        require(msg.sender == address(lender), "NFTFlashBorrower: untrusted lender");
        require(initiator == address(this), "NFTFlashBorrower: untrusted initiator");

        // do some stuff with the NFT
        // ... stuff stuff stuff
        // ... stuff stuff stuff

        // approve the lender to transfer the NFT from this contract
        ERC721(token).setApprovalForAll(address(lender), true);

        // approve the lender to take the fee from this contract
        if (lender.flashFeeToken() != address(0)) {
            ERC20(lender.flashFeeToken()).approve(msg.sender, fee);
        }

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function onERC721Received(address, address, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
