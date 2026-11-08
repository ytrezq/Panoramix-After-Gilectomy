// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { Fixtures } from "./utils/Fixtures.sol";
import { KATCustomOFTUpgradeable } from "../../contracts/KATCustomOFTUpgradeable.sol";

contract KATCustomOFTUpgradeableTest is Fixtures {
    using OptionsBuilder for bytes;

    KATCustomOFTUpgradeable customOFT;
    address user = makeAddr("user");
    address nonOwner = makeAddr("nonOwner");

    function setUp() public override {
        super.setUp();

        // Deploy custom OFT with transparent proxy
        customOFT = KATCustomOFTUpgradeable(
            _deployContractAndProxy(
                type(KATCustomOFTUpgradeable).creationCode,
                abi.encode(address(endpoints[aEid])),
                abi.encodeWithSelector(KATCustomOFTUpgradeable.initialize.selector, "Custom OFT", "COFT", address(this))
            )
        );

        // Set up peers for cross-chain testing
        customOFT.setPeer(bEid, bytes32(bytes20(address(customOFT))));

        // Mint some tokens to user for testing
        deal(address(customOFT), user, 100 ether);
    }

    function test_initialization() public view {
        assertEq(customOFT.name(), "Custom OFT");
        assertEq(customOFT.symbol(), "COFT");
        assertEq(customOFT.owner(), address(this));
        assertFalse(customOFT.paused());
    }

    function test_revertWhen_initializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        customOFT.initialize("New OFT", "NOFT", address(this));
    }

    function test_implementation_initialization_disabled() public {
        // Get implementation address from proxy
        bytes32 implementationRaw = vm.load(address(customOFT), IMPLEMENTATION_SLOT);
        address implementationAddress = address(uint160(uint256(implementationRaw)));

        KATCustomOFTUpgradeable implementation = KATCustomOFTUpgradeable(implementationAddress);

        // Try to initialize implementation directly (should fail)
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize("Hack OFT", "HOFT", address(this));
    }

    function test_pause() public {
        assertFalse(customOFT.paused());

        customOFT.pause();

        assertTrue(customOFT.paused());
    }

    function test_unpause() public {
        customOFT.pause();
        assertTrue(customOFT.paused());

        customOFT.unpause();

        assertFalse(customOFT.paused());
    }

    function test_revertWhen_pauseFromNonOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        customOFT.pause();
    }

    function test_revertWhen_unpauseFromNonOwner() public {
        customOFT.pause();

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        customOFT.unpause();
    }

    function test_multiplePauseCycles() public {
        // First cycle
        customOFT.pause();
        assertTrue(customOFT.paused());
        customOFT.unpause();
        assertFalse(customOFT.paused());

        // Second cycle
        customOFT.pause();
        assertTrue(customOFT.paused());
        customOFT.unpause();
        assertFalse(customOFT.paused());
    }

    function test_send_whenNotPaused() public {
        uint256 tokensToSend = 1 ether;

        SendParam memory sendParam = SendParam({
            dstEid: bEid,
            to: bytes32(bytes20(user)),
            amountLD: tokensToSend,
            minAmountLD: tokensToSend,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = customOFT.quoteSend(sendParam, false);

        uint256 userBalanceBefore = customOFT.balanceOf(user);

        vm.deal(user, 10 ether);
        vm.prank(user);
        customOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(user));

        uint256 userBalanceAfter = customOFT.balanceOf(user);

        // Tokens should be burned/debited
        assertLt(userBalanceAfter, userBalanceBefore);
    }

    function test_revertWhen_sendWhenPaused() public {
        customOFT.pause();

        uint256 tokensToSend = 1 ether;

        SendParam memory sendParam = SendParam({
            dstEid: bEid,
            to: bytes32(bytes20(user)),
            amountLD: tokensToSend,
            minAmountLD: tokensToSend,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = customOFT.quoteSend(sendParam, false);

        vm.deal(user, 10 ether);
        vm.prank(user);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        customOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(user));
    }

    function test_transferWhilePaused() public {
        // Standard ERC20 transfers should still work when paused
        // (only bridge functionality via _debit is paused)

        uint256 transferAmount = 1 ether;
        uint256 userBalanceBefore = customOFT.balanceOf(user);

        customOFT.pause();

        vm.prank(user);
        customOFT.transfer(nonOwner, transferAmount);

        assertEq(customOFT.balanceOf(user), userBalanceBefore - transferAmount);
        assertEq(customOFT.balanceOf(nonOwner), transferAmount);
    }

    function test_transferOwnership() public {
        address newOwner = makeAddr("newOwner");

        customOFT.transferOwnership(newOwner);

        assertEq(customOFT.owner(), newOwner);
    }

    function test_pauseByNewOwner() public {
        address newOwner = makeAddr("newOwner");

        customOFT.transferOwnership(newOwner);

        vm.prank(newOwner);
        customOFT.pause();

        assertTrue(customOFT.paused());
    }

    function test_revertWhen_oldOwnerTriesToPause() public {
        address oldOwner = address(this);
        address newOwner = makeAddr("newOwner");

        customOFT.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, oldOwner));
        customOFT.pause();
    }

    function test_statePersistence_duringPauseCycle() public {
        // Check initial state
        uint256 totalSupply = customOFT.totalSupply();
        uint256 userBalance = customOFT.balanceOf(user);
        string memory name = customOFT.name();
        string memory symbol = customOFT.symbol();

        // Pause and unpause
        customOFT.pause();
        customOFT.unpause();

        // State should be unchanged
        assertEq(customOFT.totalSupply(), totalSupply);
        assertEq(customOFT.balanceOf(user), userBalance);
        assertEq(customOFT.name(), name);
        assertEq(customOFT.symbol(), symbol);
    }

    function test_fuzz_sendAmounts(uint256 amount) public {
        // Use reasonable bounds to avoid dust amounts and overflow
        vm.assume(amount >= 1 ether && amount <= 50 ether);

        SendParam memory sendParam = SendParam({
            dstEid: bEid,
            to: bytes32(bytes20(user)),
            amountLD: amount,
            minAmountLD: 0, // Set to 0 to avoid slippage issues in testing
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0),
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = customOFT.quoteSend(sendParam, false);

        uint256 balanceBefore = customOFT.balanceOf(user);

        vm.deal(user, 10 ether);
        vm.prank(user);
        customOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(user));

        uint256 balanceAfter = customOFT.balanceOf(user);

        // Balance should decrease after send
        assertLt(balanceAfter, balanceBefore);
    }
}
