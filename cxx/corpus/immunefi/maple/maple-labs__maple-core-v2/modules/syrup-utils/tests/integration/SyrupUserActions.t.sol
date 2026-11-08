// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { DssLitePsm } from "../../modules/lite-psm/src/DssLitePsm.sol";

import { IPoolLike }        from "../../contracts/interfaces/Interfaces.sol";
import { SyrupUserActions } from "../../contracts/SyrupUserActions.sol";

import { MockReenteringSdai }   from "../utils/Mocks.sol";
import { IERC20Like, IPSMLike } from "../utils/Interfaces.sol";

contract SyrupUserActionsTestBase is Test {

    event Swap(address indexed owner, address indexed receiver, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    address constant BAL_VAULT    = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant DAI          = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant GEM_JOIN     = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address constant PSM          = 0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A;
    address constant SDAI         = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address constant SYRUP_USDC   = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;
    address constant SYRUP_SOURCE = 0xAdA1fc89b42F15A1Ce5395456CF4E0A90A9e8EfE;
    address constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_SOURCE  = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;

    bytes32 constant POOL_ID = 0x48a5bfb5bd44345db0b31fa4b5a204890695c9b4000000000000000000000697;

    address account  = makeAddr("account");
    address receiver = makeAddr("receiver");

    // Balances at forked block
    uint256 daiSupply        = 3_216_775_619.466151466516065926e18;
    uint256 syrupUsdcBalance = 500e6;
    uint256 syrupUsdcIn      = 1e6;
    uint256 usdcBalance      = 572_618_775.164220e6;

    IERC20Like dai       = IERC20Like(DAI);
    IERC20Like usdc      = IERC20Like(USDC);
    IERC20Like syrupUsdc = IERC20Like(SYRUP_USDC);

    Vm.Wallet accountWallet = vm.createWallet("account");

    SyrupUserActions syrupUserActions;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 20184000);

        syrupUserActions = new SyrupUserActions(DAI, PSM, SDAI, SYRUP_USDC, POOL_ID);

        _mintSyrupUsdc(address(account), syrupUsdcIn);
    }

    function _burnSyrupUsdc(address from_, uint256 amount_) internal {
        vm.prank(from_);
        IERC20Like(SYRUP_USDC).transfer(address(0), amount_);
    }

    function _getPermitDigest(
        address asset_,
        address owner_,
        address spender_,
        uint256 value_,
        uint256 nonce_,
        uint256 deadline_
    )
        internal view returns (bytes32 digest_)
    {
        IERC20Like asset = IERC20Like(asset_);

        return keccak256(
            abi.encodePacked(
                '\x19\x01',
                asset.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(asset.PERMIT_TYPEHASH(), owner_, spender_, value_, nonce_, deadline_))
            )
        );
    }

    function _mintUSDC(address to_, uint256 amount_) internal {
        vm.prank(USDC_SOURCE);
        IERC20Like(USDC).transfer(to_, amount_);
    }

    function _mintSyrupUsdc(address to_, uint256 amount_) internal {
        vm.prank(SYRUP_SOURCE);
        IERC20Like(SYRUP_USDC).transfer(to_, amount_);
    }

    // Replaces the old PSM contract with the new `LitePsm`.
    function _setupLitePsm() internal {
        IPSMLike psm = IPSMLike(PSM);

        // The `gemJoin` contract contains all the USDC liquidity.
        address gemJoin = psm.gemJoin();

        // Create a `LitePsm` contract with the `gem` set as USDC and the `pocket` pointing to `gemJoin`.
        address litePsm = address(new DssLitePsm(psm.ilk(), USDC, psm.daiJoin(), gemJoin));

        // Ensure `LitePsm` can spend `gem` (USDC) on behalf of the `pocket` (`gemJoin`).
        vm.prank(gemJoin);
        usdc.approve(PSM, type(uint256).max);

        // Finally, replace the old bytecode.
        vm.etch(PSM, litePsm.code);
    }

}

contract SyrupUserActionsConstructorTests is SyrupUserActionsTestBase {

    function testFork_constructor() external {
        syrupUserActions = new SyrupUserActions(DAI, PSM, SDAI, SYRUP_USDC, POOL_ID);

        assertEq(syrupUserActions.BAL_VAULT(),     0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        assertEq(syrupUserActions.dai(),           0x6B175474E89094C44Da98b954EedeAC495271d0F);
        assertEq(syrupUserActions.poolId(),        POOL_ID);
        assertEq(syrupUserActions.psm(),           0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A);
        assertEq(syrupUserActions.PSM_PRECISION(), 1e12);
        assertEq(syrupUserActions.sDai(),          0x83F20F44975D03b1b09e64809B757c47f942BEeA);
        assertEq(syrupUserActions.syrupUsdc(),     0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b);
        assertEq(syrupUserActions.USDC(),          0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        bytes32 locked = vm.load(address(syrupUserActions), bytes32(0));

        assertEq(uint256(locked), 1);

        assertEq(syrupUsdc.allowance(address(syrupUserActions), BAL_VAULT), type(uint256).max);
        assertEq(dai.allowance(address(syrupUserActions), PSM), type(uint256).max);
    }

}

contract SwapToUsdcTestsWithLivePsm is SyrupUserActionsTestBase {

    function testFork_swapToUsdc_noApproval() external {
        vm.expectRevert("SUA:S:TRANSFER_FROM_FAILED");
        syrupUserActions.swapToUsdc(syrupUsdcIn, 0, block.timestamp, receiver);
    }

    function testFork_swapToUsdcWithPermit_expired() external {
        uint256 deadline  = block.timestamp - 1 seconds;
        address depositor = accountWallet.addr;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        vm.expectRevert("ERC20:P:EXPIRED");
        vm.prank(account);
        syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToUsdcWithPermit_invalidSignatureDueToInvalidNonce() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    1,
            deadline_: deadline
            })
        );

        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        vm.prank(account);
        syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToUsdcWithPermit_insufficientPermitAmount() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn - 1,
            nonce_:    0,
            deadline_: deadline
            })
        );

        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        vm.prank(account);
        syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToUsdc_insufficientBalance() external {
        // Burn syrupUSDC
        _burnSyrupUsdc(account, 1);

        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        vm.expectRevert("SUA:S:TRANSFER_FROM_FAILED");
        syrupUserActions.swapToUsdc(syrupUsdcIn, 0, block.timestamp, receiver);
    }

    function testFork_swapToUsdcWithPermit_insufficientBalance() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        // Burn syrupUSDC
        _burnSyrupUsdc(account, 1);

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        vm.expectRevert("SUA:S:TRANSFER_FROM_FAILED");
        vm.prank(account);
        syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToUsdc_notEnoughOut() external {
        _mintSyrupUsdc(address(account), syrupUsdcIn);

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        vm.expectRevert("SUA:S:INSUFFICIENT_AMOUNT_OUT");
        vm.prank(account);
        syrupUserActions.swapToUsdc(syrupUsdcIn, 100e6, block.timestamp, receiver);
    }

    function testFork_swapToUsdcWithPermit_notEnoughOut() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        vm.expectRevert("SUA:S:INSUFFICIENT_AMOUNT_OUT");
        vm.prank(account);
        syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, 100e6, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToUsdc_reentrancy() external {
        _mintSyrupUsdc(address(account), syrupUsdcIn);

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        address reentrantSdai = address(new MockReenteringSdai(address(syrupUserActions)));
        vm.etch(SDAI, reentrantSdai.code);

        vm.expectRevert("SUA:LOCKED");
        vm.prank(account);
        syrupUserActions.swapToUsdc(syrupUsdcIn, 0, block.timestamp, receiver);
    }

    function testFork_swapToUsdcWithPermit_reentrancy() external {
        _mintSyrupUsdc(address(account), syrupUsdcIn);

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    account,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: block.timestamp
            })
        );

        address reentrantSdai = address(new MockReenteringSdai(address(syrupUserActions)));
        vm.etch(SDAI, reentrantSdai.code);

        vm.expectRevert("SUA:LOCKED");
        vm.prank(account);
        syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, block.timestamp, v, r, s);
    }

    function testFork_swapToUsdc_success() public {
        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minOutput  = poolOutput * 0.995e18 / 1e18;

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         0);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance);

        vm.expectEmit();
        emit Swap(account, receiver, SYRUP_USDC, syrupUsdcIn, USDC, 1.001996e6);

        vm.prank(account);
        uint256 usdcOut = syrupUserActions.swapToUsdc(syrupUsdcIn, minOutput, block.timestamp, receiver);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         usdcOut);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance - usdcOut);

        assertTrue(usdcOut >= minOutput);
    }

    function testFork_swapToUsdc_success_sameReceiver() public {
        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minOutput  = poolOutput * 0.995e18 / 1e18;

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance);

        vm.expectEmit();
        emit Swap(account, account, SYRUP_USDC, syrupUsdcIn, USDC, 1.001996e6);

        vm.prank(account);
        uint256 usdcOut = syrupUserActions.swapToUsdc(syrupUsdcIn, minOutput, block.timestamp, account);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(usdc.balanceOf(address(account)),          usdcOut);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance - usdcOut);

        assertTrue(usdcOut >= minOutput);
    }

    function testFork_swapToUsdcWithPermit_success() external {
        address depositor  = accountWallet.addr;
        uint256 deadline   = block.timestamp;
        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minOutput  = poolOutput * 0.995e18 / 1e18;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         0);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance);

        vm.expectEmit();
        emit Swap(account, receiver, SYRUP_USDC, syrupUsdcIn, USDC, 1.001996e6);

        vm.prank(account);
        uint256 usdcOut = syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, minOutput, block.timestamp, receiver, deadline, v, r, s);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         usdcOut);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance - usdcOut);

        assertTrue(usdcOut >= minOutput);
    }

    function testFork_swapToUsdcWithPermit_success_sameReceiver() external {
        address depositor  = accountWallet.addr;
        uint256 deadline   = block.timestamp;
        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minOutput  = poolOutput * 0.995e18 / 1e18;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance);

        vm.expectEmit();
        emit Swap(account, account, SYRUP_USDC, syrupUsdcIn, USDC, 1.001996e6);

        vm.prank(account);
        uint256 usdcOut = syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, minOutput, block.timestamp, account, deadline, v, r, s);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(usdc.balanceOf(address(account)),          usdcOut);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance - usdcOut);

        assertTrue(usdcOut >= minOutput);
    }

    function testFork_swapToUsdc_nonZeroTout() external {
        __setTout(0.1e18); // 10% Fee on PSM

        assertEq(IPSMLike(PSM).tout(), 0.1e18);

        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minOutput  = poolOutput * 0.9e18 / 1e18;

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         0);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance);

        vm.prank(account);
        uint256 usdcOut = syrupUserActions.swapToUsdc(syrupUsdcIn, minOutput, block.timestamp, receiver);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         usdcOut);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance - usdcOut);

        assertTrue(usdcOut >= minOutput);
    }

    function testForkFuzz_swapToUsdc_withTout(uint256 syrupUsdcIn_, uint256 slippage_, uint256 tout_) external {
        // Burn existing amount of syrupUsdc in the account
        _burnSyrupUsdc(account, syrupUsdcIn);

        // Increase this value once the balancer pool has more liquidity
        syrupUsdcIn = bound(syrupUsdcIn_, 1e5,      400e6);
        tout_       = bound(tout_,        0.002e18, 0.01e18);  // 0.01e18 = 1%
        slippage_   = bound(slippage_,    0.002e18, 0.01e18);

        uint256 minUsdcOut = syrupUsdcIn * (1e18 - (slippage_ + tout_)) / 1e18;

        __setTout(tout_);

        assertEq(IPSMLike(PSM).tout(), tout_);

        _mintSyrupUsdc(address(account), syrupUsdcIn);

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         0);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance);

        vm.prank(account);
        uint256 usdcOut = syrupUserActions.swapToUsdc(syrupUsdcIn, minUsdcOut, block.timestamp, receiver);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         usdcOut);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance - usdcOut);

        assertTrue(usdcOut >= minUsdcOut);
    }

    function testForkFuzz_swapToUsdcWithPermit_success(uint256 amountIn_, uint256 slippage_) external {
        // Burn existing amount of syrupUsdc in the account
        _burnSyrupUsdc(account, syrupUsdcIn);

        address depositor  = accountWallet.addr;
        uint256 deadline   = block.timestamp;

        syrupUsdcIn = bound(amountIn_, 2,  400e6);
        slippage_   = bound(slippage_, 20, 100);  // From 20 to 100 bps

        uint256 minUsdcOut = syrupUsdcIn * (10000 - slippage_) / 10000;

        _mintSyrupUsdc(address(account), syrupUsdcIn);

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn ,
            nonce_:    0,
            deadline_: deadline
            })
        );

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         0);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance);

        vm.prank(account);
        uint256 usdcOut = syrupUserActions.swapToUsdcWithPermit(syrupUsdcIn, minUsdcOut, block.timestamp, receiver, deadline, v, r, s);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(usdc.balanceOf(address(account)),          0);
        assertEq(usdc.balanceOf(address(receiver)),         usdcOut);
        assertEq(usdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(usdc.balanceOf(GEM_JOIN),                  usdcBalance - usdcOut);

        assertTrue(usdcOut >= minUsdcOut);
    }

    function __setTout(uint256 tout_) internal {
        address ward = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

        vm.prank(ward);
        IPSMLike(PSM).file("tout", tout_);  // 1e18 or WAD is a 100% fee
    }

}

contract SwapToDaiTestsWithLivePsm is SyrupUserActionsTestBase {

    function testFork_swapToDai_noApproval() external {
        vm.expectRevert("SUA:S:TRANSFER_FROM_FAILED");
        syrupUserActions.swapToDai(syrupUsdcIn, 0, block.timestamp, receiver);
    }

    function testFork_swapToDaiWithPermit_expired() external {
        uint256 deadline  = block.timestamp - 1 seconds;
        address depositor = accountWallet.addr;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        vm.expectRevert("ERC20:P:EXPIRED");
        vm.prank(account);
        syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToDaiWithPermit_invalidSignatureDueToInvalidNonces() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    1,
            deadline_: deadline
            })
        );

        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        vm.prank(account);
        syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToDaiWithPermit_insufficientPermitAmount() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn - 1,
            nonce_:    0,
            deadline_: deadline
            })
        );

        vm.expectRevert("ERC20:P:INVALID_SIGNATURE");
        vm.prank(account);
        syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToDai_insufficientBalance() external {
        _mintSyrupUsdc(address(account), syrupUsdcIn - 1);

        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        vm.expectRevert("SUA:S:TRANSFER_FROM_FAILED");
        syrupUserActions.swapToDai(syrupUsdcIn, 0, block.timestamp, receiver);
    }

    function testFork_swapToDaiWithPermit_insufficientBalance() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        _burnSyrupUsdc(account, 1);

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        vm.expectRevert("SUA:S:TRANSFER_FROM_FAILED");
        vm.prank(account);
        syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToDai_notEnoughOut() external {
        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        vm.expectRevert("SUA:S:INSUFFICIENT_AMOUNT_OUT");
        vm.prank(account);
        syrupUserActions.swapToDai(syrupUsdcIn, 100e18, block.timestamp, receiver);
    }

    function testFork_swapToDaiWithPermit_notEnoughOut() external {
        uint256 deadline  = block.timestamp;
        address depositor = accountWallet.addr;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        vm.expectRevert("SUA:S:INSUFFICIENT_AMOUNT_OUT");
        vm.prank(account);
        syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, 100e18, block.timestamp, receiver, deadline, v, r, s);
    }

    function testFork_swapToDai_reentrancy() external {
        _mintSyrupUsdc(address(account), syrupUsdcIn);

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        address reentrantSdai = address(new MockReenteringSdai(address(syrupUserActions)));
        vm.etch(SDAI, reentrantSdai.code);

        vm.expectRevert("SUA:LOCKED");
        vm.prank(account);
        syrupUserActions.swapToDai(syrupUsdcIn, 0, block.timestamp, receiver);
    }

    function testFork_swapToDaiWithPermit_reentrancy() external {
        _mintSyrupUsdc(address(account), syrupUsdcIn);

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    account,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: block.timestamp
            })
        );

        address reentrantSdai = address(new MockReenteringSdai(address(syrupUserActions)));
        vm.etch(SDAI, reentrantSdai.code);

        vm.expectRevert("SUA:LOCKED");
        vm.prank(account);
        syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, 0, block.timestamp, receiver, block.timestamp, v, r, s);
    }

    function testFork_swapToDai_success() public {
        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minDaiOut  = poolOutput * 0.995e18 / 1e18;

        uint256 initialSdaiBalance = IERC20Like(SDAI).balanceOf(address(BAL_VAULT));

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(dai.balanceOf(address(account)),          0);
        assertEq(dai.balanceOf(address(receiver)),         0);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply);

        vm.expectEmit();
        emit Swap(account, receiver, SYRUP_USDC, syrupUsdcIn, DAI, 1.001996538096073486e18);

        vm.prank(account);
        uint256 daiOut = syrupUserActions.swapToDai(syrupUsdcIn, minDaiOut, block.timestamp, receiver);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(dai.balanceOf(address(account)),          0);
        assertEq(dai.balanceOf(address(receiver)),         daiOut);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply + daiOut);

        assertTrue(initialSdaiBalance > IERC20Like(SDAI).balanceOf(address(BAL_VAULT)));

        assertTrue(daiOut >= minDaiOut);
    }

    function testFork_swapToDai_success_sameReceiver() public {
        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minDaiOut  = poolOutput * 0.995e18 / 1e18;

        uint256 initialSdaiBalance = IERC20Like(SDAI).balanceOf(address(BAL_VAULT));

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(dai.balanceOf(address(account)),          0);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply);

        vm.expectEmit();
        emit Swap(account, account, SYRUP_USDC, syrupUsdcIn, DAI, 1.001996538096073486e18);

        vm.prank(account);
        uint256 daiOut = syrupUserActions.swapToDai(syrupUsdcIn, minDaiOut, block.timestamp, account);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(dai.balanceOf(address(account)),          daiOut);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply + daiOut);

        assertTrue(initialSdaiBalance > IERC20Like(SDAI).balanceOf(address(BAL_VAULT)));

        assertTrue(daiOut >= minDaiOut);
    }

    function testFork_swapToDaiWithPermit_success() external {
        address depositor  = accountWallet.addr;
        uint256 deadline   = block.timestamp;
        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minDaiOut  = poolOutput * 0.995e18 / 1e18;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        uint256 initialSdaiBalance = IERC20Like(SDAI).balanceOf(address(BAL_VAULT));

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(dai.balanceOf(address(account)),          0);
        assertEq(dai.balanceOf(address(receiver)),         0);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply);

        vm.expectEmit();
        emit Swap(account, receiver, SYRUP_USDC, syrupUsdcIn, DAI, 1.001996538096073486e18);

        vm.prank(account);
        uint256 daiOut = syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, minDaiOut, block.timestamp, receiver, deadline, v, r, s);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(dai.balanceOf(address(account)),          0);
        assertEq(dai.balanceOf(address(receiver)),         daiOut);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply + daiOut);

        assertTrue(initialSdaiBalance > IERC20Like(SDAI).balanceOf(address(BAL_VAULT)));

        assertTrue(daiOut >= minDaiOut);
    }

    function testFork_swapToDaiWithPermit_success_sameReceiver() external {
        address depositor  = accountWallet.addr;
        uint256 deadline   = block.timestamp;
        uint256 poolOutput = IPoolLike(SYRUP_USDC).convertToExitAssets(syrupUsdcIn);
        uint256 minDaiOut  = poolOutput * 0.995e18 / 1e18;

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn,
            nonce_:    0,
            deadline_: deadline
            })
        );

        uint256 initialSdaiBalance = IERC20Like(SDAI).balanceOf(address(BAL_VAULT));

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(dai.balanceOf(address(account)),                0);
        assertEq(dai.balanceOf(address(syrupUserActions)),       0);

        assertEq(dai.totalSupply(), daiSupply);

        vm.expectEmit();
        emit Swap(account, account, SYRUP_USDC, syrupUsdcIn, DAI, 1.001996538096073486e18);

        vm.prank(account);
        uint256 daiOut = syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, minDaiOut, block.timestamp, account, deadline, v, r, s);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(dai.balanceOf(address(account)),          daiOut);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply + daiOut);

        assertTrue(initialSdaiBalance > IERC20Like(SDAI).balanceOf(address(BAL_VAULT)));

        assertTrue(daiOut >= minDaiOut);
    }

    function testForkFuzz_swapToDai(uint256 amount_, uint256 slippage_) external {
        _burnSyrupUsdc(account, syrupUsdcIn);

        // Increase this value once the balancer pool has more liquidity
        syrupUsdcIn = bound(amount_,   2,  400e6);
        slippage_   = bound(slippage_, 10, 100);  // From 10 to 100 bps

        uint256 minDaiOut = syrupUsdcIn * (10000 - slippage_) / 10000;

        uint256 initialSdaiBalance = IERC20Like(SDAI).balanceOf(address(BAL_VAULT));

        _mintSyrupUsdc(address(account), syrupUsdcIn);

        vm.prank(account);
        syrupUsdc.approve(address(syrupUserActions), syrupUsdcIn);

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance);

        assertEq(dai.balanceOf(address(account)),          0);
        assertEq(dai.balanceOf(address(receiver)),         0);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply);

        vm.prank(account);
        uint256 daiOut = syrupUserActions.swapToDai(syrupUsdcIn, minDaiOut, block.timestamp, receiver);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(syrupUsdc.balanceOf(BAL_VAULT),                 syrupUsdcBalance + syrupUsdcIn);

        assertEq(dai.balanceOf(address(account)),          0);
        assertEq(dai.balanceOf(address(receiver)),         daiOut);
        assertEq(dai.balanceOf(address(syrupUserActions)), 0);

        assertEq(dai.totalSupply(), daiSupply + daiOut);

        assertTrue(initialSdaiBalance > IERC20Like(SDAI).balanceOf(address(BAL_VAULT)));

        assertTrue(daiOut >= minDaiOut);
    }

    function testForkFuzz_swapToDaiWithPermit_success(uint256 amount_, uint256 slippage_) external {
        _burnSyrupUsdc(account, syrupUsdcIn);

        address depositor  = accountWallet.addr;
        uint256 deadline   = block.timestamp;

        syrupUsdcIn = bound(amount_,   2,  400e6);
        slippage_   = bound(slippage_, 20, 100);  // From 20 to 100 bps

        uint256 minDaiOut = syrupUsdcIn * (10000 - slippage_) / 10000;

        _mintSyrupUsdc(address(account), syrupUsdcIn);

        uint256 initialSdaiBalance = IERC20Like(SDAI).balanceOf(address(BAL_VAULT));

        ( uint8 v, bytes32 r, bytes32 s ) = vm.sign(accountWallet, _getPermitDigest({
            asset_:    address(syrupUsdc),
            owner_:    depositor,
            spender_:  address(syrupUserActions),
            value_:    syrupUsdcIn ,
            nonce_:    0,
            deadline_: deadline
            })
        );

        assertEq(syrupUsdc.balanceOf(address(account)),          syrupUsdcIn);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(dai.balanceOf(address(account)),                0);
        assertEq(dai.balanceOf(address(receiver)),               0);
        assertEq(dai.balanceOf(address(syrupUserActions)),       0);

        vm.prank(account);
        uint256 daiOut = syrupUserActions.swapToDaiWithPermit(syrupUsdcIn, minDaiOut, block.timestamp, receiver, deadline, v, r, s);

        assertEq(syrupUsdc.balanceOf(address(account)),          0);
        assertEq(syrupUsdc.balanceOf(address(syrupUserActions)), 0);
        assertEq(dai.balanceOf(address(account)),                0);
        assertEq(dai.balanceOf(address(receiver)),               daiOut);
        assertEq(dai.balanceOf(address(syrupUserActions)),       0);

        assertTrue(initialSdaiBalance > IERC20Like(SDAI).balanceOf(address(BAL_VAULT)));

        assertTrue(daiOut >= minDaiOut);
    }

}

contract SwapToUsdcTestsWithLitePsm is SwapToUsdcTestsWithLivePsm {

    function setUp() public virtual override {
        super.setUp();

        _setupLitePsm();
    }

}

contract SwapToDaiTestsWithLitePsm is SwapToDaiTestsWithLivePsm {

    function setUp() public virtual override {
        super.setUp();

        _setupLitePsm();
    }

}
