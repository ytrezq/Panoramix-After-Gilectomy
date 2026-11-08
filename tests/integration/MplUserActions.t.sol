// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { MplUserActions } from "../../contracts/MplUserActions.sol";

import { TestBase } from "./TestBase.t.sol";

contract MplUserActionsTestBase is TestBase {

    event MigratedAndStaked(
        address indexed sender,
        address assetSent,
        uint256 amountSent,
        address indexed receiver,
        address assetReceived,
        uint256 amountReceived
    );

    event RedeemedAndMigrated(
        address indexed sender,
        address assetSent,
        uint256 amountSent,
        address indexed receiver,
        address assetReceived,
        uint256 amountReceived
    );

    event RedeemedAndMigratedAndStaked(
        address indexed sender,
        address assetSent,
        uint256 amountSent,
        address indexed receiver,
        address assetReceived,
        uint256 amountReceived
    );

    // NOTE: Syrup initializer always mints the same amount (ignoring scalar).
    uint256 mplSupply   = 10_000_000e18;
    uint256 syrupSupply = mplSupply;

    // NOTE: xMPL and stSYRUP do not have any additional accrued value.
    uint256 mplIn      = 1_000e18;
    uint256 xmplIn     = mplIn;
    uint256 syrupOut   = mplIn * scalar;
    uint256 stsyrupOut = syrupOut;

    MplUserActions actions;

    function setUp() public virtual override {
        super.setUp();

        actions = new MplUserActions(address(migrator), address(xmpl), address(stsyrup));
    }

}

contract MigrateAndStakeTests is MplUserActionsTestBase {

    function test_integration_migrateAndStake_zeroAmount() external {
        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:ZERO_AMOUNT");
        actions.migrateAndStake(receiver.addr, 0);
    }

    function test_integration_migrateAndStake_insufficientApproval() external {
        vm.prank(sender.addr);
        mpl.approve(address(actions), mplIn - 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:TRANSFER_FAIL");
        actions.migrateAndStake(receiver.addr, mplIn);
    }

    function test_integration_migrateAndStake_insufficientBalance() external {
        vm.prank(sender.addr);
        mpl.approve(address(actions), mplSupply + 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:TRANSFER_FAIL");
        actions.migrateAndStake(receiver.addr, mplSupply + 1);
    }

    function test_integration_migrateAndStake_migratorInactive() external {
        vm.prank(sender.addr);
        mpl.approve(address(actions), mplIn);

        vm.prank(sender.addr);
        vm.expectRevert("M:M:INACTIVE");
        actions.migrateAndStake(receiver.addr, mplIn);
    }

    function test_integration_migrateAndStake_success() external {
        vm.prank(governor.addr);
        migrator.setActive(true);

        vm.prank(sender.addr);
        mpl.approve(address(actions), mplIn);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             mplSupply,            uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupSupply,       uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.expectEmit();
        emit MigratedAndStaked(sender.addr, address(mpl), mplIn, receiver.addr, address(stsyrup), stsyrupOut);

        vm.prank(sender.addr);
        uint256 amount = actions.migrateAndStake(receiver.addr, mplIn);

        uint256 syrupDiff = syrupSupply - syrupOut;
        uint256 mplDiff   = mplSupply - mplIn;

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             mplDiff,              uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupDiff,         uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}

contract MigrateAndStakeWithPermitTests is MplUserActionsTestBase {

    function test_integration_migrateAndStakeWithPermit_expiredDeadline() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        vm.warp(block.timestamp + 1 seconds);
        vm.prank(sender.addr);
        vm.expectRevert("MapleToken:EXPIRED");
        actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp - 1 seconds, v, r, s);
    }

    function test_integration_migrateAndStakeWithPermit_malleable() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        v *= 2;

        // NOTE: `MapleToken` has no explicit `MALLEABLE` revert.
        vm.prank(sender.addr);
        vm.expectRevert("MapleToken:INVALID_SIGNATURE");
        actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp, v, r, s);
    }

    function test_integration_migrateAndStakeWithPermit_invalidSignature() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        s <<= 1;

        vm.prank(sender.addr);
        vm.expectRevert("MapleToken:INVALID_SIGNATURE");
        actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp, v, r, s);
    }

    function test_integration_migrateAndStakeWithPermit_zeroAmount() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), 0, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:ZERO_AMOUNT");
        actions.migrateAndStakeWithPermit(receiver.addr, 0, block.timestamp, v, r, s);
    }

    function test_integration_migrateAndStakeWithPermit_insufficientBalance() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplSupply + 1, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:TRANSFER_FAIL");
        actions.migrateAndStakeWithPermit(receiver.addr, mplSupply + 1, block.timestamp, v, r, s);
    }

    function test_integration_migrateAndStakeWithPermit_migratorInactive() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("M:M:INACTIVE");
        actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp, v, r, s);
    }

    function test_integration_migrateAndStakeWithPermit_success() external {
        vm.prank(governor.addr);
        migrator.setActive(true);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             mplSupply,            uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupSupply,       uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.expectEmit();
        emit MigratedAndStaked(sender.addr, address(mpl), mplIn, receiver.addr, address(stsyrup), stsyrupOut);

        vm.prank(sender.addr);
        uint256 amount = actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp, v, r, s);

        uint256 syrupDiff = syrupSupply - syrupOut;
        uint256 mplDiff   = mplSupply - mplIn;

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             mplDiff,              uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupDiff,         uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}

contract RedeemAndMigrateTests is MplUserActionsTestBase {

    function test_integration_redeemAndMigrate_zeroAmount() external {
        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:ZERO_AMOUNT");
        actions.redeemAndMigrate(receiver.addr, 0);
    }

    function test_integration_redeemAndMigrate_insufficientApproval() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn - 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:TRANSFER_FAIL");
        actions.redeemAndMigrate(receiver.addr, xmplIn);
    }

    function test_integration_redeemAndMigrate_insufficientBalance() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn + 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:TRANSFER_FAIL");
        actions.redeemAndMigrate(receiver.addr, xmplIn + 1);
    }

    function test_integration_redeemAndMigrate_migratorInactive() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn);

        vm.prank(sender.addr);
        vm.expectRevert("M:M:INACTIVE");
        actions.redeemAndMigrate(receiver.addr, xmplIn);
    }

    function test_integration_redeemAndMigrate_success() external {
        vm.prank(governor.addr);
        migrator.setActive(true);

        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             mplSupply - mplIn,    uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             xmplIn,               uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupSupply,       uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.expectEmit();
        emit RedeemedAndMigrated(sender.addr, address(xmpl), xmplIn, receiver.addr, address(syrup), syrupOut);

        vm.prank(sender.addr);
        uint256 amount = actions.redeemAndMigrate(receiver.addr, xmplIn);

        uint256 mplDiff   = mplSupply - mplIn;
        uint256 syrupDiff = syrupSupply - syrupOut;

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             mplDiff,              uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupDiff,         syrupOut,               uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}

contract RedeemAndMigrateWithPermitTests is MplUserActionsTestBase {

    function test_integration_redeemAndMigrateWithPermit_expiredDeadline() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.warp(block.timestamp + 1 seconds);
        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:EXPIRED");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp - 1 seconds, v, r, s);
    }

    function test_integration_redeemAndMigrateWithPermit_malleable() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        v *= 2;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:MALLEABLE");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateWithPermit_invalidSignature() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        r >>= 1;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateWithPermit_zeroAmount() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), 0, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:ZERO_AMOUNT");
        actions.redeemAndMigrateWithPermit(receiver.addr, 0, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateWithPermit_insufficientBalance() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn + 1, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:TRANSFER_FAIL");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn + 1, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateWithPermit_migratorInactive() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("M:M:INACTIVE");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateWithPermit_success() external {
        vm.prank(governor.addr);
        migrator.setActive(true);

        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             mplSupply - mplIn,    uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             xmplIn,               uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupSupply,       uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.expectEmit();
        emit RedeemedAndMigrated(sender.addr, address(xmpl), xmplIn, receiver.addr, address(syrup), syrupOut);

        vm.prank(sender.addr);
        uint256 amount = actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);

        uint256 mplDiff   = mplSupply - mplIn;
        uint256 syrupDiff = syrupSupply - syrupOut;

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             mplDiff,              uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupDiff,         syrupOut,               uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}

contract RedeemAndMigrateAndStakeTests is MplUserActionsTestBase {

    function test_integration_redeemAndMigrateAndStake_zeroAmount() external {
        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:ZERO_AMOUNT");
        actions.redeemAndMigrateAndStake(receiver.addr, 0);
    }

    function test_integration_redeemAndMigrateAndStake_insufficientApproval() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn - 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:TRANSFER_FAIL");
        actions.redeemAndMigrateAndStake(receiver.addr, xmplIn);
    }

    function test_integration_redeemAndMigrateAndStake_insufficientBalance() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn + 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:TRANSFER_FAIL");
        actions.redeemAndMigrateAndStake(receiver.addr, xmplIn + 1);
    }

    function test_integration_redeemAndMigrateAndStake_migratorInactive() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn);

        vm.prank(sender.addr);
        vm.expectRevert("M:M:INACTIVE");
        actions.redeemAndMigrateAndStake(receiver.addr, xmplIn);
    }

    function test_integration_redeemAndMigrateAndStake_success() external {
        vm.prank(governor.addr);
        migrator.setActive(true);

        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             mplSupply - mplIn,    uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             xmplIn,               uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupSupply,       uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.expectEmit();
        emit RedeemedAndMigratedAndStaked(sender.addr, address(xmpl), xmplIn, receiver.addr, address(stsyrup), stsyrupOut);

        vm.prank(sender.addr);
        uint256 amount = actions.redeemAndMigrateAndStake(receiver.addr, xmplIn);

        uint256 syrupDiff = syrupSupply - syrupOut;
        uint256 mplDiff   = mplSupply - mplIn;

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             mplDiff,              uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupDiff,         uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}

contract RedeemAndMigrateAndStakeWithPermitTests is MplUserActionsTestBase {

    function test_integration_redeemAndMigrateAndStakeWithPermit_expiredDeadline() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.warp(block.timestamp + 1 seconds);
        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:EXPIRED");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp - 1 seconds, v, r, s);
    }

    function test_integration_redeemAndMigrateAndStakeWithPermit_malleable() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        v *= 2;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:MALLEABLE");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateAndStakeWithPermit_invalidSignature() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        r >>= 1;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateAndStakeWithPermit_zeroAmount() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), 0, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:ZERO_AMOUNT");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, 0, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateAndStakeWithPermit_insufficientBalance() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn + 1, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:TRANSFER_FAIL");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn + 1, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateAndStakeWithPermit_migratorInactive() external {
        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("M:M:INACTIVE");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_integration_redeemAndMigrateAndStakeWithPermit_success() external {
        vm.prank(governor.addr);
        migrator.setActive(true);

        vm.prank(sender.addr);
        mpl.approve(address(xmpl), mplIn);

        vm.prank(sender.addr);
        xmpl.deposit(mplIn, sender.addr);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             mplSupply - mplIn,    uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             xmplIn,               uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupSupply,       uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.expectEmit();
        emit RedeemedAndMigratedAndStaked(sender.addr, address(xmpl), xmplIn, receiver.addr, address(stsyrup), stsyrupOut);

        vm.prank(sender.addr);
        uint256 amount = actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);

        uint256 syrupDiff = syrupSupply - syrupOut;
        uint256 mplDiff   = mplSupply - mplIn;

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             mplDiff,              uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       syrupDiff,         uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}
