// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { SyrupRouter } from "../../contracts/SyrupRouter.sol";

import {
    MockERC20,
    MockPool,
    MockPoolManager,
    MockPoolPermissionManager
} from "../utils/Mocks.sol";

contract SyrupRouterTests is Test {

    event DepositData(address indexed owner, uint256 amount, bytes32 depositData);

    address account = makeAddr("account");
    address ppa     = makeAddr("permissionAdmin");

    bytes32 functionId = "P:deposit";

    uint256 amount         = 2;
    uint256 bitmap         = 1;
    uint256 authDeadline   = block.timestamp;
    uint256 permitDeadline = block.timestamp;

    MockERC20                 asset;
    MockPoolManager           pm;
    MockPool                  pool;
    MockPoolPermissionManager ppm;

    SyrupRouter router;

    Vm.Wallet accountWallet;
    Vm.Wallet ppaWallet;

    function setUp() public {
        asset = new MockERC20("USDC", "USDC", 6);
        ppm   = new MockPoolPermissionManager();
        pm    = new MockPoolManager(address(ppm));
        pool  = new MockPool("MaplePool", "MP", 18, address(asset), address(pm));

        router = new SyrupRouter(address(pool));

        accountWallet = vm.createWallet("account");
        ppaWallet     = vm.createWallet("permissionAdmin");

        asset.mint(account, amount);
    }

    function test_constructor_approveFails() external {
        asset.__setApproveReverts(true);

        vm.expectRevert("SR:C:APPROVE_FAIL");
        router = new SyrupRouter(address(pool));
    }

    function test_constructor_success() external {
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockPool.asset.selector));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockPool.manager.selector));
        vm.expectCall(address(pm),    abi.encodeWithSelector(MockPoolManager.poolPermissionManager.selector));
        vm.expectCall(address(asset), abi.encodeWithSelector(MockERC20.approve.selector, address(pool), type(uint256).max));

        router = new SyrupRouter(address(pool));

        assertEq(router.asset(),                 address(asset));
        assertEq(router.pool(),                  address(pool));
        assertEq(router.poolManager(),           address(pm));
        assertEq(router.poolPermissionManager(), address(ppm));

        assertEq(asset.allowance(address(router), address(pool)), type(uint256).max);
    }

    function test_authorizeAndDeposit_expired() external {
        authDeadline = block.timestamp - 1;

        vm.expectRevert("SR:A:EXPIRED");
        router.authorizeAndDeposit(bitmap, authDeadline, 0, bytes32(0), bytes32(0), amount, bytes32(0));
    }

    function test_authorizeAndDeposit_malleable() external {
        uint8 v = 2;

        vm.expectRevert("SR:A:MALLEABLE");
        router.authorizeAndDeposit(bitmap, authDeadline, v, bytes32(0), bytes32(0), amount, bytes32(0));
    }

    function test_authorizeAndDeposit_notPermissionAdmin() external {
        ppm.__setPermissionAdmins(false);

        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(ppaWallet, _getAuthDigest(address(router), account, bitmap, authDeadline));

        vm.prank(account);
        vm.expectRevert("SR:A:NOT_PERMISSION_ADMIN");
        router.authorizeAndDeposit(bitmap, authDeadline, v, r, s, amount, bytes32(0));
    }

    function test_authorizeAndDeposit_success() external {
        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(ppaWallet, _getAuthDigest(address(router), account, bitmap, authDeadline));

        address[] memory lenders = new address[](1);
        lenders[0] = account;

        uint256[] memory bitmaps = new uint256[](1);
        bitmaps[0] = bitmap;

        vm.prank(account);
        asset.approve(address(router), amount);

        vm.expectCall(address(ppm), abi.encodeWithSelector(MockPoolPermissionManager.permissionAdmins.selector, address(ppa)));
        vm.expectCall(address(ppm), abi.encodeWithSelector(MockPoolPermissionManager.setLenderBitmaps.selector, lenders, bitmaps));

        vm.expectCall(address(ppm), abi.encodeWithSelector(
            MockPoolPermissionManager.hasPermission.selector, address(pm), account, functionId)
        );

        vm.expectCall(address(asset), abi.encodeWithSelector(MockERC20.transferFrom.selector, account, address(router), amount));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockPool.deposit.selector, amount, address(router)));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockERC20.transfer.selector, account, amount));

        assertEq(asset.balanceOf(account),       amount);
        assertEq(asset.balanceOf(address(pool)), 0);

        assertEq(pool.balanceOf(account), 0);
        assertEq(pool.totalSupply(),      0);

        vm.expectEmit();
        emit DepositData(account, amount, bytes32(0));

        vm.prank(account);
        router.authorizeAndDeposit(bitmap, authDeadline, v, r, s, amount, bytes32(0));

        assertEq(asset.balanceOf(account),       0);
        assertEq(asset.balanceOf(address(pool)), amount);

        assertEq(pool.balanceOf(account), amount);
        assertEq(pool.totalSupply(),      amount);
    }

    function test_authorizeAndDepositWithPermit_expired() external {
        authDeadline = block.timestamp - 1;

        vm.expectRevert("SR:A:EXPIRED");
        router.authorizeAndDepositWithPermit(
            bitmap, authDeadline, 0, bytes32(0), bytes32(0), amount, bytes32(0), block.timestamp, 0, bytes32(0), bytes32(0)
        );
    }

    function test_authorizeAndDepositWithPermit_malleable() external {
        uint8 v = 2;

        vm.expectRevert("SR:A:MALLEABLE");
        router.authorizeAndDepositWithPermit(
            bitmap, authDeadline, v, bytes32(0), bytes32(0), amount, bytes32(0), block.timestamp, 0, bytes32(0), bytes32(0)
        );
    }

    function test_authorizeAndDepositWithPermit_notPermissionAdmin() external {
        ppm.__setPermissionAdmins(false);

        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(ppaWallet, _getAuthDigest(address(router), account, bitmap, authDeadline));

        vm.expectRevert("SR:A:NOT_PERMISSION_ADMIN");
        router.authorizeAndDepositWithPermit(
            bitmap, authDeadline, v, r, s, amount, bytes32(0), block.timestamp, 0, bytes32(0), bytes32(0)
        );
    }

    function test_authorizeAndDepositWithPermit_success() external {
        // Get both signatures
        (uint8 auth_v , bytes32 auth_r, bytes32 auth_s ) = vm.sign(ppaWallet, _getAuthDigest(
            address(router), account, bitmap, authDeadline));

        (uint8 permit_v , bytes32 permit_r, bytes32 permit_s ) = vm.sign(accountWallet, _getPermitDigest(
            account, address(router), amount, 0, permitDeadline));

        address[] memory lenders = new address[](1);
        lenders[0] = account;

        uint256[] memory bitmaps = new uint256[](1);
        bitmaps[0] = bitmap;

        vm.expectCall(address(ppm), abi.encodeWithSelector(MockPoolPermissionManager.permissionAdmins.selector, address(ppa)));
        vm.expectCall(address(ppm), abi.encodeWithSelector(MockPoolPermissionManager.setLenderBitmaps.selector, lenders, bitmaps));

        vm.expectCall(
            address(asset),
            abi.encodeWithSelector(
                MockERC20.permit.selector,
                account,
                address(router),
                amount,
                permitDeadline,
                permit_v,
                permit_r,
                permit_s
            )
        );

        vm.expectCall(
            address(ppm),
            abi.encodeWithSelector(MockPoolPermissionManager.hasPermission.selector, address(pm), account, functionId)
        );

        vm.expectCall(address(asset), abi.encodeWithSelector(MockERC20.transferFrom.selector, account, address(router), amount));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockPool.deposit.selector, amount, address(router)));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockERC20.transfer.selector, account, amount));

        assertEq(asset.balanceOf(account),       amount);
        assertEq(asset.balanceOf(address(pool)), 0);

        assertEq(pool.balanceOf(account), 0);
        assertEq(pool.totalSupply(),      0);

        vm.expectEmit();

        emit DepositData(account, amount, bytes32(0));

        vm.prank(account);
        router.authorizeAndDepositWithPermit(
            bitmap,
            authDeadline,
            auth_v,
            auth_r,
            auth_s,
            amount,
            bytes32(0),
            permitDeadline,
            permit_v,
            permit_r,
            permit_s
        );

        assertEq(asset.balanceOf(account),       0);
        assertEq(asset.balanceOf(address(pool)), amount);

        assertEq(pool.balanceOf(account), amount);
        assertEq(pool.totalSupply(),      amount);
    }

    function test_deposit_notAuthorized() external {
        ppm.__setHasPermission(false);

        vm.prank(account);
        vm.expectRevert("SR:D:NOT_AUTHORIZED");
        router.deposit(amount, bytes32(0));
    }

    function test_deposit_transferFromFails_insufficientAmount() external {
        asset.burn(account, 1);

        vm.prank(account);
        vm.expectRevert("SR:D:TRANSFER_FROM_FAIL");
        router.deposit(amount, bytes32(0));
    }

    function test_deposit_transferFromFails_insufficientApproval() external {
        vm.prank(account);
        asset.approve(address(router), amount - 1);

        vm.prank(account);
        vm.expectRevert("SR:D:TRANSFER_FROM_FAIL");
        router.deposit(amount, bytes32(0));
    }

    function test_deposit_transferFails() external {
        pool.__setTransferReverts(true);

        vm.prank(account);
        asset.approve(address(router), amount);

        vm.prank(account);
        vm.expectRevert("SR:D:TRANSFER_FAIL");
        router.deposit(amount, bytes32(0));
    }

    function test_deposit_success() external {
        vm.prank(account);
        asset.approve(address(router), amount);

        vm.expectCall(address(ppm),   abi.encodeWithSelector(
            MockPoolPermissionManager.hasPermission.selector, address(pm), account, functionId)
        );
        vm.expectCall(address(asset), abi.encodeWithSelector(MockERC20.transferFrom.selector, account, address(router), amount));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockPool.deposit.selector, amount, address(router)));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockERC20.transfer.selector, account, amount));

        assertEq(asset.balanceOf(account),       amount);
        assertEq(asset.balanceOf(address(pool)), 0);

        assertEq(pool.balanceOf(account), 0);
        assertEq(pool.totalSupply(),      0);

        vm.expectEmit();

        emit DepositData(account, amount, bytes32(0));

        vm.prank(account);
        router.deposit(amount, bytes32(0));

        assertEq(asset.balanceOf(account),       0);
        assertEq(asset.balanceOf(address(pool)), amount);

        assertEq(pool.balanceOf(account), amount);
        assertEq(pool.totalSupply(),      amount);
    }

    function test_depositWithPermit_invalidSignature() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        // Setting the incorrect nonce
        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest(depositor, address(router), amount, 1, deadline));

        // The actual error for USDC might not be this.
        vm.prank(depositor);
        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        router.depositWithPermit(amount, deadline, v, r, s, bytes32(0));
    }

        function test_depositWithPermit_expiredDeadline() external {
        uint256 deadline  = block.timestamp - 1 seconds;
        address depositor = accountWallet.addr;

        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest(depositor, address(router), amount, 0, deadline));

        vm.prank(depositor);
        vm.expectRevert("ERC20:P:EXPIRED");
        router.depositWithPermit(amount, deadline , v, r, s, bytes32(0));
    }

    function test_depositWithPermit_notAuthorized() external {
        ppm.__setHasPermission(false);

        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest(
            accountWallet.addr, address(router), amount, 0, deadline));

        vm.prank(depositor);
        vm.expectRevert("SR:D:NOT_AUTHORIZED");
        router.depositWithPermit(amount, deadline, v, r, s, bytes32(0));
    }

    function test_depositWithPermit_transferFromFails_insufficientAmount() external {
        asset.burn(account, 1);

        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest(
            accountWallet.addr, address(router), amount, 0, deadline));

        vm.prank(depositor);
        vm.expectRevert("SR:D:TRANSFER_FROM_FAIL");
        router.depositWithPermit(amount, deadline, v, r, s, bytes32(0));
    }

    function test_depositWithPermit_transferFails() external {
        pool.__setTransferReverts(true);

        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest(
            accountWallet.addr, address(router), amount, 0, deadline));

        vm.prank(depositor);
        vm.expectRevert("SR:D:TRANSFER_FAIL");
        router.depositWithPermit(amount, deadline, v, r, s, bytes32(0));
    }

    function test_depositWithPermit_success() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        (uint8 v , bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest(depositor, address(router), amount, 0, deadline));

        vm.expectCall(
            address(asset),
            abi.encodeWithSelector(MockERC20.permit.selector, depositor, address(router), amount, deadline, v, r, s)
        );

        vm.expectCall(
            address(ppm),
            abi.encodeWithSelector(MockPoolPermissionManager.hasPermission.selector, address(pm), depositor, functionId)
        );

        vm.expectCall(address(asset), abi.encodeWithSelector(MockERC20.transferFrom.selector, depositor, address(router), amount));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockPool.deposit.selector, amount, address(router)));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockERC20.transfer.selector, depositor, amount));

        assertEq(asset.balanceOf(depositor),     amount);
        assertEq(asset.balanceOf(address(pool)), 0);

        assertEq(pool.balanceOf(depositor), 0);
        assertEq(pool.totalSupply(),        0);

        vm.expectEmit();

        emit DepositData(account, amount, bytes32(0));

        vm.prank(depositor);
        router.depositWithPermit(amount, deadline, v, r, s, bytes32(0));

        assertEq(asset.balanceOf(depositor),     0);
        assertEq(asset.balanceOf(address(pool)), amount);

        assertEq(pool.balanceOf(depositor), amount);
        assertEq(pool.totalSupply(),        amount);
    }

    function test_depositWithPermit_skipPermit() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        vm.prank(depositor);
        asset.approve(address(router), amount);

        ( uint8 v , bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest(depositor, address(router), amount, 0, deadline));

        vm.expectCall(
            address(ppm),
            abi.encodeWithSelector(MockPoolPermissionManager.hasPermission.selector, address(pm), depositor, functionId)
        );

        vm.expectCall(address(asset), abi.encodeWithSelector(MockERC20.transferFrom.selector, depositor, address(router), amount));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockPool.deposit.selector, amount, address(router)));
        vm.expectCall(address(pool),  abi.encodeWithSelector(MockERC20.transfer.selector, depositor, amount));

        assertEq(asset.balanceOf(depositor),     amount);
        assertEq(asset.balanceOf(address(pool)), 0);

        assertEq(pool.balanceOf(depositor), 0);
        assertEq(pool.totalSupply(),        0);

        vm.expectEmit();
        emit DepositData(account, amount, bytes32(0));

        vm.prank(depositor);
        router.depositWithPermit(amount, deadline, v, r, s, bytes32(0));

        assertEq(asset.balanceOf(depositor),     0);
        assertEq(asset.balanceOf(address(pool)), amount);

        assertEq(pool.balanceOf(depositor), amount);
        assertEq(pool.totalSupply(),        amount);
    }

    /**************************************************************************************************************************************/
    /*** Helpers                                                                                                                        ***/
    /**************************************************************************************************************************************/

    function _getPermitDigest(
        address owner_,
        address spender_,
        uint256 value_,
        uint256 nonce_,
        uint256 deadline_
    )
        internal view returns (bytes32 digest_)
    {
        return keccak256(
            abi.encodePacked(
                '\x19\x01',
                asset.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(asset.PERMIT_TYPEHASH(), owner_, spender_, value_, nonce_, deadline_))
            )
        );
    }

    function _getAuthDigest(
        address router_,
        address owner_,
        uint256 bitmap_,
        uint256 deadline_
    )
        internal view returns (bytes32 digest_)
    {
        return keccak256(abi.encodePacked(
            '\x19\x01',
            block.chainid,
            router_,
            owner_,
            SyrupRouter(router_).nonces(owner_),
            bitmap_,
            deadline_
        ));
    }

}
