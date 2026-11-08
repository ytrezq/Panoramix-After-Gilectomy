// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {Fixtures} from "./utils/Fixtures.sol";
import {KATVaultMock} from "./utils/KATVaultMock.sol";
import {KATCustomOFTAdapterUpgradeable, IKATVault} from "../../contracts/KATCustomOFTAdapterUpgradeable.sol";

contract KATCustomOFTAdapterUpgradeableTest is Fixtures {
    IKATVault KATVault;
    KATCustomOFTAdapterUpgradeable customOFTAdapter;
    address bridgeUser = makeAddr("bridgeUser");

    function setUp() public override {
        super.setUp();
        customOFTAdapter = KATCustomOFTAdapterUpgradeable(
            _deployContractAndProxy(
                type(KATCustomOFTAdapterUpgradeable).creationCode,
                abi.encode(address(erc20Mock), address(endpoints[aEid])),
                abi.encodeWithSelector(KATCustomOFTAdapterUpgradeable.initialize.selector, address(this))
            )
        );
        customOFTAdapter.setPeer(aEid, bytes32(bytes20(address(4242))));
        customOFTAdapter.setPeer(bEid, bytes32(bytes20(address(4242))));
        customOFTAdapter.grantRole(customOFTAdapter.BRIDGE_USER(), bridgeUser);

        KATVault = new KATVaultMock();
        customOFTAdapter.setVault(address(KATVault));
    }

    function test_grantBridgeUser() public {
        customOFTAdapter.grantBridgeUser(address(this));

        assertTrue(customOFTAdapter.isBridgeUser(address(this)));
    }

    function test_revertWhen_grantBridgeUserFromNonAdmin() public {
        vm.prank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(1), 0x00)
        );
        customOFTAdapter.grantBridgeUser(address(1));
    }

    function test_revokeBridgeUser() public {
        customOFTAdapter.revokeBridgeUser(bridgeUser);
        assertFalse(customOFTAdapter.isBridgeUser(bridgeUser));
    }

    function test_revertWhen_revokeBridgeUserFromNonAdmin() public {
        vm.prank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(1), 0x00)
        );
        customOFTAdapter.revokeBridgeUser(bridgeUser);
    }

    function test_debit() public {
        deal(bridgeUser, 100 ether);
        SendParam memory params = SendParam({
            dstEid: bEid,
            to: bytes32(bytes20(address(this))),
            amountLD: 1 ether,
            minAmountLD: 0.9 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = customOFTAdapter.quoteSend(params, false);

        vm.prank(bridgeUser);
        vm.mockCall(address(customOFTAdapter), abi.encodeWithSelector(IKATVault.transferKat.selector), "");
        vm.expectEmit();
        emit KATCustomOFTAdapterUpgradeable.BridgeInitiated(bridgeUser, bEid, 1 ether);
        customOFTAdapter.send{value: fee.nativeFee}(params, fee, address(this));
    }

    function test_revertWhen_debitFromNonBridgeUser() public {
        SendParam memory params = SendParam({
            dstEid: bEid,
            to: bytes32(bytes20(address(this))),
            amountLD: 1 ether,
            minAmountLD: 0.9 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = customOFTAdapter.quoteSend(params, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), customOFTAdapter.BRIDGE_USER()
            )
        );
        customOFTAdapter.send{value: fee.nativeFee}(params, fee, address(this));
    }

    function test_setVault() public {
        vm.expectEmit();
        emit KATCustomOFTAdapterUpgradeable.VaultUpdated(address(KATVault), address(1));
        customOFTAdapter.setVault(address(1));

        assertEq(address(customOFTAdapter.getVault()), address(1), "KAT vault should have ben updated");
    }

    function test_revertWhen_setVaultWithAddress0() public {
        vm.expectRevert("KATCustomOFTAdapter: vault is zero address");
        customOFTAdapter.setVault(address(0));
    }

    function test_revertWhen_setVaultFromNonOwnerAddress() public {
        vm.prank(bridgeUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bridgeUser));
        customOFTAdapter.setVault(address(1));
    }

    function test_initialize() public {
        customOFTAdapter = KATCustomOFTAdapterUpgradeable(
            _deployContractAndProxy(
                type(KATCustomOFTAdapterUpgradeable).creationCode,
                abi.encode(address(erc20Mock), address(endpoints[aEid])),
                ""
            )
        );

        assertFalse(customOFTAdapter.hasRole(customOFTAdapter.DEFAULT_ADMIN_ROLE(), address(this)));
        assertEq(customOFTAdapter.owner(), address(0));

        address endpoint = address(customOFTAdapter.endpoint());
        vm.expectEmit(endpoint);
        emit ILayerZeroEndpointV2.DelegateSet(address(customOFTAdapter), address(this));
        vm.expectEmit(address(customOFTAdapter));
        emit Initializable.Initialized(1);
        customOFTAdapter.initialize(address(this));
        assertTrue(customOFTAdapter.hasRole(customOFTAdapter.DEFAULT_ADMIN_ROLE(), address(this)));
        assertEq(customOFTAdapter.owner(), address(this));
    }
    
    function test_revertWhen_initializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        customOFTAdapter.initialize(address(this));
    }

    function test_initializated_disableOnImplementationContract() public {
        bytes32 implementationRaw = vm.load(address(customOFTAdapter), IMPLEMENTATION_SLOT);
        address implementationAddress = address(uint160(uint256(implementationRaw)));

        KATCustomOFTAdapterUpgradeable oftAdapterImplementation = KATCustomOFTAdapterUpgradeable(implementationAddress);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oftAdapterImplementation.initialize(address(this));
    }
}
