// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {EthRouter} from "../src/EthRouter.sol";
import {Factory} from "../src/Factory.sol";
import {PrivatePool} from "../src/PrivatePool.sol";
import {PrivatePoolMetadata} from "../src/PrivatePoolMetadata.sol";

contract DeployScript is Script {
    function run() public {
        vm.startBroadcast();

        EthRouter ethRouter = new EthRouter(vm.envAddress("ROYALTY_REGISTRY"));
        console.log("eth router:", address(ethRouter));

        // Factory factory = new Factory();
        // console.log("factory:", address(factory));

        // PrivatePool privatePoolImplementation =
        //     new PrivatePool(address(factory), vm.envAddress("ROYALTY_REGISTRY"), vm.envAddress("STOLEN_NFT_ORACLE"));
        // console.log("private pool implementation:", address(privatePoolImplementation));

        // PrivatePoolMetadata privatePoolMetadata = new PrivatePoolMetadata();
        // console.log("private pool metadata", address(privatePoolMetadata));

        // factory.setPrivatePoolImplementation(address(privatePoolImplementation));
        // factory.setPrivatePoolMetadata(address(privatePoolMetadata));

        vm.stopBroadcast();
    }
}
