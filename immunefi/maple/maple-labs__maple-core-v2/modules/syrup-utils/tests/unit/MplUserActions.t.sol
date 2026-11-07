// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { MplUserActions } from "../../contracts/MplUserActions.sol";

import { MockERC20, MockMigrator, MockRDT } from "../utils/Mocks.sol";

contract MplUserActionsTestBase is Test {

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

    uint8   decimals = 18;
    uint256 scalar   = 100;

    uint256 xmplIn     = 15e18;
    uint256 mplIn      = xmplIn;
    uint256 syrupOut   = mplIn * scalar;
    uint256 stsyrupOut = syrupOut;

    Vm.Wallet sender;
    Vm.Wallet receiver;

    MockMigrator migrator;
    MockERC20    mpl;
    MockERC20    syrup;
    MockRDT      xmpl;
    MockRDT      stsyrup;

    MplUserActions actions;

    function setUp() public virtual {
        sender   = vm.createWallet("sender");
        receiver = vm.createWallet("receiver");

        mpl      = new MockERC20("Maple Token", "MPL", decimals);
        syrup    = new MockERC20("Syrup", "SYRUP", decimals);
        xmpl     = new MockRDT("xMPL", "xMPL", decimals, mpl);
        stsyrup  = new MockRDT("Staked Syrup", "stSYRUP", decimals, syrup);
        migrator = new MockMigrator(mpl, syrup, scalar);

        actions = new MplUserActions(address(migrator), address(xmpl), address(stsyrup));
    }

    function assertBalances(
        address[6] memory accounts,
        uint256[6] memory mpls,
        uint256[6] memory xmpls,
        uint256[6] memory syrups,
        uint256[6] memory stsyrups
    )
        internal view
    {
        for (uint256 i; i < accounts.length; i++) {
            assertEq(mpl.balanceOf(address(accounts[i])),     mpls[i]);
            assertEq(xmpl.balanceOf(address(accounts[i])),    xmpls[i]);
            assertEq(syrup.balanceOf(address(accounts[i])),   syrups[i]);
            assertEq(stsyrup.balanceOf(address(accounts[i])), stsyrups[i]);
        }
    }

    function signPermit(
        address asset,
        Vm.Wallet memory owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    )
        internal returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 digest = keccak256(abi.encodePacked(
            '\x19\x01',
            MockERC20(asset).DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                MockERC20(asset).PERMIT_TYPEHASH(),
                owner.addr,
                spender,
                value,
                nonce,
                deadline
            ))
        ));

        ( v, r, s ) = vm.sign(owner, digest);
    }

}

contract MplUserActionsConstructorTests is MplUserActionsTestBase {

    function test_constructor() external {
        actions = new MplUserActions(address(migrator), address(xmpl), address(stsyrup));

        assertEq(actions.migrator(), address(migrator));
        assertEq(actions.mpl(),      address(mpl));
        assertEq(actions.syrup(),    address(syrup));
        assertEq(actions.xmpl(),     address(xmpl));
        assertEq(actions.stsyrup(),  address(stsyrup));

        assertEq(mpl.allowance(address(actions),   address(migrator)), type(uint256).max);
        assertEq(syrup.allowance(address(actions), address(stsyrup)),  type(uint256).max);
    }

}

contract MplUserActionsMigrateAndStakeTests is MplUserActionsTestBase {

    function setUp() public virtual override {
        super.setUp();

        mpl.mint(sender.addr, mplIn);
    }

    function test_migrateAndStake_zeroAmount() external {
        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:ZERO_AMOUNT");
        actions.migrateAndStake(receiver.addr, 0);
    }

    function test_migrateAndStake_insufficientApproval() external {
        vm.prank(sender.addr);
        mpl.approve(address(actions), mplIn - 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:TRANSFER_FAIL");
        actions.migrateAndStake(receiver.addr, mplIn);
    }

    function test_migrateAndStake_insufficientBalance() external {
        mpl.burn(sender.addr, 1);

        vm.prank(sender.addr);
        mpl.approve(address(actions), mplIn);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:TRANSFER_FAIL");
        actions.migrateAndStake(receiver.addr, mplIn);
    }

    function test_migrateAndStake_differentReceiver() external {
        vm.prank(sender.addr);
        mpl.approve(address(actions), mplIn);

        vm.expectEmit();
        emit MigratedAndStaked(sender.addr, address(mpl), mplIn, receiver.addr, address(stsyrup), stsyrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             mplIn,                uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(sender.addr);
        uint256 amount = actions.migrateAndStake(receiver.addr, mplIn);

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

    function test_migrateAndStake_sameReceiver() external {
        mpl.burn(sender.addr,   mplIn);
        mpl.mint(receiver.addr, mplIn);

        vm.prank(receiver.addr);
        mpl.approve(address(actions), mplIn);

        vm.expectEmit();
        emit MigratedAndStaked(receiver.addr, address(mpl), mplIn, receiver.addr, address(stsyrup), stsyrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        mplIn,                  uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(receiver.addr);
        uint256 amount = actions.migrateAndStake(receiver.addr, mplIn);

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

    function testFuzz_migrateAndStake() external {
        // TODO: Fuzz: sender.addr, receiver.addr, amounts, exchange rates (scalars).
    }

}

contract MplUserActionsMigrateAndStakeWithPermitTests is MplUserActionsTestBase {

    function setUp() public virtual override {
        super.setUp();

        mpl.mint(sender.addr, mplIn);
    }

    function test_migrateAndStakeWithPermit_expiredDeadline() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        vm.warp(block.timestamp + 1 seconds);
        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:EXPIRED");
        actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp - 1 seconds, v, r, s);
    }

    function test_migrateAndStakeWithPermit_malleable() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        v *= 2;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:MALLEABLE");
        actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp, v, r, s);
    }

    function test_migrateAndStakeWithPermit_invalidSignature() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        s <<= 1;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp, v, r, s);
    }

    function test_migrateAndStakeWithPermit_zeroAmount() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), 0, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:ZERO_AMOUNT");
        actions.migrateAndStakeWithPermit(receiver.addr, 0, block.timestamp, v, r, s);
    }

    function test_migrateAndStakeWithPermit_insufficientBalance() external {
        mpl.burn(sender.addr, 1);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:MAS:TRANSFER_FAIL");
        actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp, v, r, s);
    }

    function test_migrateAndStakeWithPermit_success() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(mpl), sender, address(actions), mplIn, 0, block.timestamp);

        vm.expectEmit();
        emit MigratedAndStaked(sender.addr, address(mpl), mplIn, receiver.addr, address(stsyrup), stsyrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             mplIn,                uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(sender.addr);
        uint256 amount = actions.migrateAndStakeWithPermit(receiver.addr, mplIn, block.timestamp, v, r, s);

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}

contract MplUserActionsRedeemAndMigrateTests is MplUserActionsTestBase {

    function setUp() public virtual override {
        super.setUp();

        mpl.mint(address(xmpl), mplIn);
        xmpl.mint(sender.addr,  xmplIn);
    }

    function test_redeemAndMigrate_zeroAmount() external {
        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:ZERO_AMOUNT");
        actions.redeemAndMigrate(receiver.addr, 0);
    }

    function test_redeemAndMigrate_insufficientApproval() external {
        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn - 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:TRANSFER_FAIL");
        actions.redeemAndMigrate(receiver.addr, xmplIn);
    }

    function test_redeemAndMigrate_insufficientBalance() external {
        xmpl.burn(sender.addr, 1);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:TRANSFER_FAIL");
        actions.redeemAndMigrate(receiver.addr, xmplIn);
    }

    function test_redeemAndMigrate_differentReceiver() external {
        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn);

        vm.expectEmit();
        emit RedeemedAndMigrated(sender.addr, address(xmpl), xmplIn, receiver.addr, address(syrup), syrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             xmplIn,               uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(sender.addr);
        uint256 amount = actions.redeemAndMigrate(receiver.addr, xmplIn);

        assertEq(amount, syrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        syrupOut,               uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });
    }

    function test_redeemAndMigrate_sameReceiver() external {
        xmpl.burn(sender.addr,   xmplIn);
        xmpl.mint(receiver.addr, xmplIn);

        vm.prank(receiver.addr);
        xmpl.approve(address(actions), xmplIn);

        vm.expectEmit();
        emit RedeemedAndMigrated(receiver.addr, address(xmpl), xmplIn, receiver.addr, address(syrup), syrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        xmplIn,                 uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(receiver.addr);
        uint256 amount = actions.redeemAndMigrate(receiver.addr, xmplIn);

        assertEq(amount, syrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        syrupOut,               uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });
    }

    function testFuzz_redeemAndMigrate() external {
        // TODO: Fuzz: sender.addr, receiver.addr, amounts, exchange rates (scalars).
    }

}

contract MplUserActionsRedeemAndMigrateWithPermitTests is MplUserActionsTestBase {

    function setUp() public virtual override {
        super.setUp();

        mpl.mint(address(xmpl), mplIn);
        xmpl.mint(sender.addr,  xmplIn);
    }

    function test_redeemAndMigrateWithPermit_expiredDeadline() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.warp(block.timestamp + 1 seconds);
        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:EXPIRED");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp - 1 seconds, v, r, s);
    }

    function test_redeemAndMigrateWithPermit_malleable() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        v *= 2;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:MALLEABLE");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_redeemAndMigrateWithPermit_invalidSignature() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        s <<= 1;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_redeemAndMigrateWithPermit_zeroAmount() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), 0, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:ZERO_AMOUNT");
        actions.redeemAndMigrateWithPermit(receiver.addr, 0, block.timestamp, v, r, s);
    }

    function test_redeemAndMigrateWithPermit_insufficientBalance() external {
        xmpl.burn(sender.addr, 1);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAM:TRANSFER_FAIL");
        actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_redeemAndMigrateWithPermit_success() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.expectEmit();
        emit RedeemedAndMigrated(sender.addr, address(xmpl), xmplIn, receiver.addr, address(syrup), syrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             xmplIn,               uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(sender.addr);
        uint256 amount = actions.redeemAndMigrateWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);

        assertEq(amount, syrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        syrupOut,               uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}

contract MplUserActionsRedeemAndMigrateAndStakeTests is MplUserActionsTestBase {

    function setUp() public virtual override {
        super.setUp();

        mpl.mint(address(xmpl), mplIn);
        xmpl.mint(sender.addr,  xmplIn);
    }

    function test_redeemAndMigrateAndStake_zeroAmount() external {
        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:ZERO_AMOUNT");
        actions.redeemAndMigrateAndStake(receiver.addr, 0);
    }

    function test_redeemAndMigrateAndStake_insufficientApproval() external {
        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn - 1);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:TRANSFER_FAIL");
        actions.redeemAndMigrateAndStake(receiver.addr, xmplIn);
    }

    function test_redeemAndMigrateAndStake_insufficientBalance() external {
        xmpl.burn(sender.addr, 1);

        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:TRANSFER_FAIL");
        actions.redeemAndMigrateAndStake(receiver.addr, xmplIn);
    }

    function test_redeemAndMigrateAndStake_differentReceiver() external {
        vm.prank(sender.addr);
        xmpl.approve(address(actions), xmplIn);

        vm.expectEmit();
        emit RedeemedAndMigratedAndStaked(sender.addr, address(xmpl), xmplIn, receiver.addr, address(stsyrup), stsyrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             xmplIn,               uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(sender.addr);
        uint256 amount = actions.redeemAndMigrateAndStake(receiver.addr, xmplIn);

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

    function test_redeemAndMigrateAndStake_sameReceiver() external {
        xmpl.burn(sender.addr,   xmplIn);
        xmpl.mint(receiver.addr, xmplIn);

        vm.prank(receiver.addr);
        xmpl.approve(address(actions), xmplIn);

        vm.expectEmit();
        emit RedeemedAndMigratedAndStaked(receiver.addr, address(xmpl), xmplIn, receiver.addr, address(stsyrup), stsyrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        xmplIn,                 uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(receiver.addr);
        uint256 amount = actions.redeemAndMigrateAndStake(receiver.addr, xmplIn);

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

    function testFuzz_redeemAndMigrateAndStake() external {
        // TODO: Fuzz: sender.addr, receiver.addr, amounts, exchange rates (scalars).
    }

}

contract MplUserActionsRedeemAndMigrateAndStakeWithPermitTests is MplUserActionsTestBase {

    function setUp() public virtual override {
        super.setUp();

        mpl.mint(address(xmpl),         mplIn);
        xmpl.mint(address(sender.addr), xmplIn);
    }

    function test_redeemAndMigrateAndStakeWithPermit_expiredDeadline() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.warp(block.timestamp + 1 seconds);
        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:EXPIRED");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp - 1 seconds, v, r, s);
    }

    function test_redeemAndMigrateAndStakeWithPermit_malleable() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        v *= 2;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:MALLEABLE");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_redeemAndMigrateAndStakeWithPermit_invalidSignature() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        s <<= 1;

        vm.prank(sender.addr);
        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_redeemAndMigrateAndStakeWithPermit_zeroAmount() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), 0, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:ZERO_AMOUNT");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, 0, block.timestamp, v, r, s);
    }

    function test_redeemAndMigrateAndStakeWithPermit_insufficientBalance() external {
        xmpl.burn(sender.addr, 1);

        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.prank(sender.addr);
        vm.expectRevert("MUA:RAMAS:TRANSFER_FAIL");
        actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);
    }

    function test_redeemAndMigrateAndStakeWithPermit_success() external {
        ( uint8 v, bytes32 r, bytes32 s ) = signPermit(address(xmpl), sender, address(actions), xmplIn, 0, block.timestamp);

        vm.expectEmit();
        emit RedeemedAndMigratedAndStaked(sender.addr, address(xmpl), xmplIn, receiver.addr, address(stsyrup), stsyrupOut);

        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       mplIn],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             xmplIn,               uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)]
        });

        vm.prank(sender.addr);
        uint256 amount = actions.redeemAndMigrateAndStakeWithPermit(receiver.addr, xmplIn, block.timestamp, v, r, s);

        assertEq(amount, stsyrupOut);
        assertBalances({
            accounts: [address(actions), address(migrator), address(receiver.addr), address(sender.addr), address(stsyrup), address(xmpl)],
            mpls:     [uint256(0),       mplIn,             uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            xmpls:    [uint256(0),       uint256(0),        uint256(0),             uint256(0),           uint256(0),       uint256(0)],
            syrups:   [uint256(0),       uint256(0),        uint256(0),             uint256(0),           syrupOut,         uint256(0)],
            stsyrups: [uint256(0),       uint256(0),        stsyrupOut,             uint256(0),           uint256(0),       uint256(0)]
        });
    }

}
