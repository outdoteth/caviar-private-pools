// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC721.sol";
import "solmate/utils/LibString.sol";
import {RoyaltyRegistry} from "royalty-registry-solidity/RoyaltyRegistry.sol";
import {Caviar, Pair} from "caviar/Caviar.sol";

import "./shared/Milady.sol";
import "./shared/ShibaInu.sol";
import "./shared/StolenNftOracle.sol";
import "./shared/Airdrop.sol";

import "../src/Factory.sol";
import "../src/PrivatePool.sol";
import "../src/EthRouter.sol";

contract Fixture is Test, ERC721TokenReceiver {
    using stdStorage for StdStorage;

    Milady public milady = new Milady();
    ShibaInu public shibaInu = new ShibaInu();
    StolenNftOracle public stolenNftOracle = new StolenNftOracle();
    Airdrop public airdrop = new Airdrop();
    RoyaltyRegistry public royaltyRegistry = new RoyaltyRegistry(address(0));
    EthRouter public ethRouter = new EthRouter(royaltyRegistry);
    Caviar public caviar = new Caviar(address(stolenNftOracle));
    PrivatePool public privatePoolImplementation = new PrivatePool();
    Factory public factory = new Factory(address(privatePoolImplementation));

    constructor() {}

    receive() external payable {}

    function generateMerkleRoot() public returns (bytes32) {
        string[] memory inputs = new string[](2);

        inputs[0] = "node";
        inputs[1] = "./test/shared/helpers/generate-merkle-root.js";

        bytes memory res = vm.ffi(inputs);
        bytes32 output = abi.decode(res, (bytes32));

        return output;
    }

    function generateMerkleProofs(uint256[] memory tokenIds, uint256[] memory weights)
        public
        returns (PrivatePool.MerkleMultiProof memory)
    {
        string[] memory inputs = new string[](4);
        inputs[0] = "node";
        inputs[1] = "./test/shared/helpers/generate-merkle-proof.js";
        inputs[2] = toHexString(abi.encode(tokenIds));
        inputs[3] = toHexString(abi.encode(weights));

        bytes memory res = vm.ffi(inputs);
        (bytes32[] memory proof, bool[] memory flags) = abi.decode(res, (bytes32[], bool[]));

        return PrivatePool.MerkleMultiProof(proof, flags);
    }

    // copied from https://github.com/dmfxyz/murky/blob/main/differential_testing/test/utils/Strings2.sol
    function toHexString(bytes memory input) public pure returns (string memory) {
        require(input.length < type(uint256).max / 2 - 1);
        bytes16 symbols = "0123456789abcdef";
        bytes memory hex_buffer = new bytes(2 * input.length + 2);
        hex_buffer[0] = "0";
        hex_buffer[1] = "x";

        uint256 pos = 2;
        uint256 length = input.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 _byte = uint8(input[i]);
            hex_buffer[pos++] = symbols[_byte >> 4];
            hex_buffer[pos++] = symbols[_byte & 0xf];
        }
        return string(hex_buffer);
    }
}
