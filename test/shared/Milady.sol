// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "solmate/tokens/ERC721.sol";
import "openzeppelin/token/common/ERC2981.sol";

contract Milady is ERC721, ERC2981 {
    uint256 public royaltyFeeRate = 0; // to 18 decimals
    address public royaltyRecipient = address(0);

    constructor() ERC721("Milady Maker", "MIL") {}

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "https://milady.io";
    }

    function mint(address to, uint256 id) public {
        _mint(to, id);
    }

    function setRoyaltyInfo(uint256 _royaltyFeeRate, address _royaltyRecipient) public {
        royaltyFeeRate = _royaltyFeeRate;
        royaltyRecipient = _royaltyRecipient;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC2981, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function royaltyInfo(uint256, uint256 salePrice) public view override returns (address, uint256) {
        return (address(0xbeefbeef), salePrice * royaltyFeeRate / 1e18);
    }
}
