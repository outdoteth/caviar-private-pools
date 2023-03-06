// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC721.sol";
import "solmate/utils/LibString.sol";

import "./shared/Milady.sol";
import "./shared/ShibaInu.sol";
import "./shared/StolenNftOracle.sol";

contract Fixture is Test, ERC721TokenReceiver {
    using stdStorage for StdStorage;

    Milady public milady = new Milady();
    ShibaInu public shibaInu = new ShibaInu();
    StolenNftOracle public stolenNftOracle = new StolenNftOracle();

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
        returns (bytes32[][] memory)
    {
        bytes32[][] memory proofs = new bytes32[][](tokenIds.length);

        string[] memory inputs = new string[](4);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            inputs[0] = "node";
            inputs[1] = "./test/shared/helpers/generate-merkle-proof.js";
            inputs[2] = LibString.toString(tokenIds[i]);
            inputs[3] = LibString.toString(weights[i]);

            bytes memory res = vm.ffi(inputs);
            bytes32[] memory output = abi.decode(res, (bytes32[]));
            proofs[i] = output;
        }

        return proofs;
    }
}
