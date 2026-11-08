// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import { EndpointV2Mock } from "@layerzerolabs/test-devtools-evm-foundry/contracts/mocks/EndpointV2Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {Fixtures} from "./utils/Fixtures.sol";
import {KATVaultMock} from "./utils/KATVaultMock.sol";
import {KATOFTAdapterUpgradeable} from "../../contracts/KATOFTAdapterUpgradeable.sol";

contract KATOFTAdapterUpgradeableTest is Fixtures {
    KATOFTAdapterUpgradeable oftAdapter;
    address bridgeUser = makeAddr("bridgeUser");

    function setUp() public override {
        super.setUp();
        oftAdapter = KATOFTAdapterUpgradeable(
            _deployContractAndProxy(
                type(KATOFTAdapterUpgradeable).creationCode,
                abi.encode(address(erc20Mock), address(endpoints[aEid])),
                abi.encodeWithSelector(KATOFTAdapterUpgradeable.initialize.selector, address(this))
            )
        );
        oftAdapter.setPeer(aEid, bytes32(bytes20(address(4242))));
        oftAdapter.setPeer(bEid, bytes32(bytes20(address(4242))));
    }

    function test_debit() public {
        erc20Mock.approve(address(oftAdapter), 1 ether);
        SendParam memory params = SendParam({
            dstEid: bEid,
            to: bytes32(bytes20(address(this))),
            amountLD: 1 ether,
            minAmountLD: 0.9 ether,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = oftAdapter.quoteSend(params, false);

        vm.expectEmit(address(erc20Mock));
        emit IERC20.Transfer(address(this), address(oftAdapter), 1 ether);
        oftAdapter.send{value: fee.nativeFee}(params, fee, address(this));
    }

    function test_initialize() public {
        // deploy
        oftAdapter = KATOFTAdapterUpgradeable(
            _deployContractAndProxy(
                type(KATOFTAdapterUpgradeable).creationCode,
                abi.encode(address(erc20Mock), address(endpoints[aEid])),
                ""
            )
        );

        assertFalse(oftAdapter.hasRole(oftAdapter.DEFAULT_ADMIN_ROLE(), address(this)));
        assertEq(oftAdapter.owner(), address(0));

        // initialize
        address endpoint = address(oftAdapter.endpoint());
        vm.expectEmit(endpoint);
        emit ILayerZeroEndpointV2.DelegateSet(address(oftAdapter), address(this));
        vm.expectEmit(address(oftAdapter));
        emit Initializable.Initialized(1);
        oftAdapter.initialize(address(this));
        assertFalse(oftAdapter.hasRole(oftAdapter.DEFAULT_ADMIN_ROLE(), address(this)), "No role should have been granted");
        assertEq(oftAdapter.owner(), address(this));
    }
    
    function test_revertWhen_initializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oftAdapter.initialize(address(this));
    }

    function test_initializated_disableOnImplementationContract() public {
        bytes32 implementationRaw = vm.load(address(oftAdapter), IMPLEMENTATION_SLOT);
        address implementationAddress = address(uint160(uint256(implementationRaw)));

        KATOFTAdapterUpgradeable oftAdapterImplementation = KATOFTAdapterUpgradeable(implementationAddress);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oftAdapterImplementation.initialize(address(this));

        EndpointV2Mock endpoint = EndpointV2Mock(address(oftAdapter.endpoint()));
        assertEq(endpoint.delegates(address(oftAdapter)), address(this));
        assertEq(endpoint.delegates(implementationAddress), address(0));
    }
}
