// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "contracts/interfaces/modules/base/IModule.sol";
import "contracts/interfaces/IIPAccount.sol";
import "contracts/interfaces/registries/IModuleRegistry.sol";
import "contracts/interfaces/registries/IIPAccountRegistry.sol";
import { IPAccountChecker } from "contracts/lib/registries/IPAccountChecker.sol";
import { IIPAccount } from "contracts/interfaces/IIPAccount.sol";

contract MockOrchestratorModule is IModule {
    using IPAccountChecker for IIPAccountRegistry;

    IIPAccountRegistry public ipAccountRegistry;
    IModuleRegistry public moduleRegistry;

    constructor(address _ipAccountRegistry, address _moduleRegistry) {
        ipAccountRegistry = IIPAccountRegistry(_ipAccountRegistry);
        moduleRegistry = IModuleRegistry(_moduleRegistry);
    }

    function name() external pure returns (string memory) {
        return "MockOrchestratorModule";
    }

    function workflowPass(address payable ipAccount) external {
        // check if ipAccount is valid
        require(ipAccountRegistry.isIpAccount(ipAccount), "MockModule: ipAccount is not valid");
        // check the caller is IPAccount's owner
        require(IIPAccount(ipAccount).owner() == msg.sender, "MockModule: caller is not ipAccount owner");

        // call modules
        // workflow does have permission to call a module
        address module1 = moduleRegistry.getModule("Module1WithPermission");
        address module2 = moduleRegistry.getModule("Module2WithPermission");
        // execute module1
        bytes memory module1Output = IIPAccount(ipAccount).execute(
            module1,
            0,
            abi.encodeWithSignature("executeSuccessfully(string)", "Module1WithPermission")
        );
        // execute module2
        IIPAccount(ipAccount).execute(
            module2,
            0,
            abi.encodeWithSignature("executeNoReturn(string)", abi.decode(module1Output, (string)))
        );
    }

    function workflowFailure(address payable ipAccount) external {
        // check if ipAccount is valid
        require(ipAccountRegistry.isIpAccount(ipAccount), "MockModule: ipAccount is not valid");
        // check the caller is IPAccount's owner
        require(IIPAccount(ipAccount).owner() == msg.sender, "MockModule: caller is not ipAccount owner");

        // call modules
        // workflow does have permission to call a module
        address module1 = moduleRegistry.getModule("Module1WithPermission");
        address module3WithoutPermission = moduleRegistry.getModule("Module3WithoutPermission");
        // workflow call 1st module
        bytes memory module1Output = IIPAccount(ipAccount).execute(
            module1,
            0,
            abi.encodeWithSignature("executeSuccessfully(string)", "Module1WithPermission")
        );
        // workflow call 2nd module WITHOUT permission
        // the call should fail
        IIPAccount(ipAccount).execute(
            module3WithoutPermission,
            0,
            abi.encodeWithSignature("executeNoReturn(string)", abi.decode(module1Output, (string)))
        );
    }
}
