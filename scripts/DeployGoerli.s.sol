// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./DeployBase.s.sol";
import {SimpleOracle} from "../contracts/mock/SimpleOracle.sol";

contract DeployGoerli is DeployBase {
    // TODO: replace with MockRegistry
    SimpleOracle mockOracle; // would be feed registry on Goerli

    address arbiter = 0x0F224d366F106296916b3aA3266DbE8478B3460f; // TODO: replace
    address swapTarget = 0xcb7b9188aDA88Cb0c991C807acc6b44097059DEc;
    address feedRegistry = address(3); // TODO: replace

    address seeroCoin = address(4); // TODO: replace
    address tokenB = address(5); // TODO: replace

    function run() public {
        console.log("Starting Goerli deployment");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        mockOracle = new SimpleOracle(seeroCoin, tokenB);

        run(arbiter, swapTarget, address(mockOracle));
    }
}
