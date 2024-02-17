// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ERC6551Registry } from "erc6551/ERC6551Registry.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Test } from "forge-std/Test.sol";

import { IPAccountImpl } from "contracts/IPAccountImpl.sol";
import { IIPAccount } from "contracts/interfaces/IIPAccount.sol";
import { IPAccountRegistry } from "contracts/registries/IPAccountRegistry.sol";
import { ModuleRegistry } from "contracts/registries/ModuleRegistry.sol";
import { AccessController } from "contracts/AccessController.sol";
import { MetaTx } from "contracts/lib/MetaTx.sol";
import { AccessPermission } from "contracts/lib/AccessPermission.sol";
import { Governance } from "contracts/governance/Governance.sol";
import { Errors } from "contracts/lib/Errors.sol";

import { MockERC721 } from "test/foundry/mocks/token/MockERC721.sol";
import { MockModule } from "test/foundry/mocks/module/MockModule.sol";
import { MockMetaTxModule } from "test/foundry/mocks/module/MockMetaTxModule.sol";

contract IPAccountMetaTxTest is Test {
    IPAccountRegistry public registry;
    IPAccountImpl public implementation;
    MockERC721 public nft = new MockERC721("MockERC721");
    ERC6551Registry public erc6551Registry = new ERC6551Registry();
    AccessController public accessController;
    ModuleRegistry public moduleRegistry;
    MockModule public module;
    MockMetaTxModule public metaTxModule;

    uint256 public ownerPrivateKey;
    uint256 public callerPrivateKey;
    address public owner;
    address public caller;
    Governance public governance;

    function setUp() public {
        governance = new Governance(address(this));
        accessController = new AccessController(address(governance));
        moduleRegistry = new ModuleRegistry(address(governance));
        ownerPrivateKey = 0xA11111;
        callerPrivateKey = 0xB22222;
        owner = vm.addr(ownerPrivateKey);
        caller = vm.addr(callerPrivateKey);

        implementation = new IPAccountImpl(address(accessController));
        registry = new IPAccountRegistry(address(erc6551Registry), address(implementation));
        accessController.initialize(address(registry), address(moduleRegistry));
        module = new MockModule(address(registry), address(moduleRegistry), "Module1WithPermission");
        metaTxModule = new MockMetaTxModule(address(registry), address(moduleRegistry), address(accessController));
        moduleRegistry.registerModule("Module1WithPermission", address(module));
        moduleRegistry.registerModule("MockMetaTxModule", address(metaTxModule));
    }

    // test called by unauthorized module with signature
    // test signature expired
    // test signature invalid
    // test signature does not match to parameters
    // test signature is not signed by signer
    // test signature signed by unauthorized signer
    // test signature signed by another contract
    // test signature signed by unauthorized contract
    // test setPermission with signature
    // reuse the signature

    function test_IPAccount_ExecutionPassWithSignature() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(caller);
        bytes memory result = metaTxModule.callAnotherModuleWithSignature(
            payable(address(ipAccount)),
            owner,
            deadline,
            signature
        );
        assertEq("test", abi.decode(result, (string)));

        assertEq(ipAccount.state(), 1);
    }

    function test_IPAccount_setPermissionWithSignature() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(accessController),
                    value: 0,
                    data: abi.encodeWithSignature(
                        "setPermission(address,address,address,bytes4,uint8)",
                        address(ipAccount),
                        address(metaTxModule),
                        address(module),
                        bytes4(0),
                        AccessPermission.ALLOW
                    ),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(caller);
        bytes memory result = metaTxModule.setPermissionThenCallOtherModules(
            payable(address(ipAccount)),
            owner,
            deadline,
            signature
        );
        assertEq("test", abi.decode(result, (string)));

        assertEq(ipAccount.state(), 2);
    }

    function test_IPAccount_revert_SignatureExpired() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = 0;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(Errors.IPAccount__ExpiredSignature.selector));
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), owner, deadline, signature);
        assertEq(ipAccount.state(), 0);
    }

    function test_IPAccount_revert_InvalidSignature() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        // bad signature
        bytes memory invalidSignature = abi.encodePacked(r, s, v + 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.IPAccount__InvalidSignature.selector));
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), owner, deadline, invalidSignature);
        assertEq(ipAccount.state(), 0);
    }

    function test_IPAccount_revert_SignatureNotMatchExecuteTargetFunction() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("UnMatchedFunction(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(Errors.IPAccount__InvalidSignature.selector));
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), owner, deadline, signature);
        assertEq(ipAccount.state(), 0);
    }

    function test_IPAccount_revert_WrongSigner() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        // wrong signer
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(callerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(Errors.IPAccount__InvalidSignature.selector));
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), owner, deadline, signature);
        assertEq(ipAccount.state(), 0);
    }

    function test_IPAccount_revert_SignatureForAnotherIPAccount() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint256 tokenId2 = 101;
        nft.mintId(owner, tokenId2);
        address account2 = registry.registerIpAccount(block.chainid, address(nft), tokenId2);
        IIPAccount ipAccount2 = IIPAccount(payable(account2));

        uint deadline = block.timestamp + 1000;

        // signature for another ipAccount
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(account2),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount2.state(),
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(Errors.IPAccount__InvalidSignature.selector));
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), owner, deadline, signature);
        assertEq(ipAccount.state(), 0);
    }

    function test_IPAccount_revert_signedByNonOwner() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        // signed by non-owner
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(callerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                address(caller),
                address(module),
                module.executeSuccessfully.selector
            )
        );
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), caller, deadline, signature);
        assertEq(ipAccount.state(), 0);
    }

    function test_IPAccount_revert_UseSignatureTwice() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        // first time pass
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), owner, deadline, signature);
        assertEq(ipAccount.state(), 1);
        // second time fail
        vm.expectRevert(abi.encodeWithSelector(Errors.IPAccount__InvalidSignature.selector));
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), owner, deadline, signature);
        assertEq(ipAccount.state(), 1);
    }

    function test_IPAccount_revert_signerZeroAddress() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        // bad signature
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(Errors.IPAccount__InvalidSigner.selector));
        vm.prank(caller);
        metaTxModule.callAnotherModuleWithSignature(payable(address(ipAccount)), address(0), deadline, signature);
        assertEq(ipAccount.state(), 0);
    }

    function test_IPAccount_revert_workflowFailureWithSig() public {
        uint256 tokenId = 100;

        nft.mintId(owner, tokenId);

        address account = registry.registerIpAccount(block.chainid, address(nft), tokenId);

        IIPAccount ipAccount = IIPAccount(payable(account));

        uint deadline = block.timestamp + 1000;

        bytes32 digest = MessageHashUtils.toTypedDataHash(
            MetaTx.calculateDomainSeparator(address(ipAccount)),
            MetaTx.getExecuteStructHash(
                MetaTx.Execute({
                    to: address(module),
                    value: 0,
                    data: abi.encodeWithSignature("executeSuccessfully(string)", "test"),
                    nonce: ipAccount.state() + 1,
                    deadline: deadline
                })
            )
        );

        // signed by non-owner
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);
        MockModule module3WithoutPermission = new MockModule(
            address(registry),
            address(moduleRegistry),
            "Module3WithoutPermission"
        );
        moduleRegistry.registerModule("Module3WithoutPermission", address(module3WithoutPermission));
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.AccessController__PermissionDenied.selector,
                address(ipAccount),
                address(metaTxModule),
                address(module3WithoutPermission),
                module3WithoutPermission.executeNoReturn.selector
            )
        );
        vm.prank(caller);
        metaTxModule.workflowFailureWithSignature(payable(address(ipAccount)), owner, deadline, signature);
        assertEq(ipAccount.state(), 0);
    }
}
