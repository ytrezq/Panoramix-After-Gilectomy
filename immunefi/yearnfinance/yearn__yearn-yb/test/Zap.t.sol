// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Setup } from "test/utils/Setup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { Protocol, YB, Curve, YBS } from "src/utils/Constants.sol";
import { Zap } from "src/Zap.sol";
import { ICurvePool } from "src/interfaces/curve/ICurvePool.sol";
import { IYBS } from "src/interfaces/ybs/IYBS.sol";

contract ZapTest is Setup {
    Zap public zap;
    IERC20 public yb;
    IERC20 public yyb;
    IERC20 public yvYyb;
    IERC20 public lpYyb;
    IERC20 public ybs;
    IERC20 public pool;
    IERC721 public veYb;

    uint256 public constant INITIAL_BALANCE = 1_000_000e18;

    function setUp() public virtual override {
        super.setUp();
        vm.createSelectFork(vm.envString("TENDERLY_URL"));

        yb = IERC20(YB.TOKEN);
        yyb = IERC20(Protocol.YTOKEN);
        pool = IERC20(Curve.POOL);
        yvYyb = IERC20(Protocol.YV_YYB);
        lpYyb = IERC20(Protocol.YV_LPYYB);
        ybs = IERC20(YBS.YBS_YB);
        veYb = IERC721(YB.VEYB);

        zap = new Zap(
            address(yb),
            address(yyb),
            address(yvYyb),
            address(lpYyb),
            address(ybs),
            address(pool),
            address(veYb)
        );
        
        _seedLiquidity();
        _fundAndApprove();
        _setYbsApprovedCaller(address(this), address(zap));
    }

    function maxApprove(IERC20 token, address spender) internal {
        token.approve(spender, type(uint256).max);
    }

    function _fundAndApprove() internal {
        // Approve
        maxApprove(yb, address(pool));
        maxApprove(yyb, address(pool));
        maxApprove(yb, address(zap));
        maxApprove(yyb, address(zap));
        maxApprove(yvYyb, address(zap));
        maxApprove(lpYyb, address(zap));
        maxApprove(pool, address(zap));
        maxApprove(yyb, address(yvYyb));
        maxApprove(yyb, address(ybs));
        maxApprove(yyb, address(pool));
        maxApprove(pool, address(lpYyb));

        // Fund
        createLock(address(this), INITIAL_BALANCE, block.timestamp + 100 days);
        toggleInfiniteLock(address(this), true);
        veYb.approve(address(zap), uint256(uint160(address(this))));
        deal(address(yb), address(this), INITIAL_BALANCE);
        deal(address(yyb), address(this), INITIAL_BALANCE);
        uint256 amount = 50_000e18;
        IERC4626(address(yvYyb)).deposit(amount, address(this));
        maxApprove(yyb, address(pool));
        maxApprove(pool, address(lpYyb));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;
        uint256 lpTokens = ICurvePool(address(pool)).add_liquidity(amounts, 0, address(this));
        IERC4626(address(lpYyb)).deposit(lpTokens, address(this));
        IYBS(address(ybs)).stakeFor(address(this), 25_000e18);
        deal(address(yb), address(this), INITIAL_BALANCE);
        deal(address(yyb), address(this), INITIAL_BALANCE);
    }

    function _seedLiquidity() internal {
        uint256 amount = 100_000e18;
        deal(address(yb), address(this), amount);
        deal(address(yyb), address(this), amount);
        maxApprove(yb, address(pool));
        maxApprove(yyb, address(pool));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;
        ICurvePool(address(pool)).add_liquidity(amounts, 0, address(this));
    }

    function test_ZapYbToYyb() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = yyb.balanceOf(address(this));
        uint256 received = zap.zap(address(yb), address(yyb), amount, 0, address(this));
        assertGt(received, 0);
        assertEq(yyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapYbToYvYyb() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = yvYyb.balanceOf(address(this));
        uint256 received = zap.zap(address(yb), address(yvYyb), amount, 0, address(this));
        assertGt(received, 0);
        assertEq(yvYyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapYbToLpYyb() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = lpYyb.balanceOf(address(this));
        uint256 received = zap.zap(address(yb), address(lpYyb), amount, 0, address(this));
        assertGt(received, 0);
        assertEq(lpYyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapYbToYbs() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = ybs.balanceOf(address(this));
        uint256 received = zap.zap(address(yb), address(ybs), amount, 0, address(this));
        assertGt(received, 0);
        assertEq(ybs.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapYybToyvYyb() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = yvYyb.balanceOf(address(this));
        uint256 received = zap.zap(address(yyb), address(yvYyb), amount, 0, address(this));
        assertGt(received, 0);
        assertEq(yvYyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapYybToLpYyb() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = lpYyb.balanceOf(address(this));
        uint256 received = zap.zap(address(yyb), address(lpYyb), amount, 0, address(this));
        assertGt(received, 0);
        assertEq(lpYyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapYybToYbs() public {
        uint256 amount = 1000e18;
        uint256 balanceBefore = ybs.balanceOf(address(this));
        uint256 received = zap.zap(address(yyb), address(ybs), amount, 0, address(this));
        assertEq(received, amount);
        assertEq(ybs.balanceOf(address(this)), balanceBefore + amount);
    }

    function test_ZapYvYybToYyb() public {
        uint256 shares = IERC4626(address(yvYyb)).deposit(1000e18, address(this));
        uint256 balanceBefore = yyb.balanceOf(address(this));
        uint256 received = zap.zap(address(yvYyb), address(yyb), shares, 0, address(this));
        assertGt(received, 0);
        assertEq(yyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapyvYybToLpYyb() public {
        uint256 shares = IERC4626(address(yvYyb)).deposit(1000e18, address(this));
        uint256 balanceBefore = lpYyb.balanceOf(address(this));
        uint256 received = zap.zap(address(yvYyb), address(lpYyb), shares, 0, address(this));
        assertGt(received, 0);
        assertEq(lpYyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapLpYybToYyb() public {
        maxApprove(yyb, address(pool));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 1000e18;
        uint256 lpTokens = ICurvePool(address(pool)).add_liquidity(amounts, 0, address(this));
        maxApprove(pool, address(lpYyb));
        uint256 shares = IERC4626(address(lpYyb)).deposit(lpTokens, address(this));
        uint256 balanceBefore = yyb.balanceOf(address(this));
        uint256 received = zap.zap(address(lpYyb), address(yyb), shares, 0, address(this));
        assertGt(received, 0);
        assertEq(yyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapYbsToYyb() public {
        uint256 ybsAmount = IYBS(address(ybs)).stakeFor(address(this), 1000e18);

        uint256 balanceBefore = yyb.balanceOf(address(this));

        uint256 received = zap.zap(address(ybs), address(yyb), ybsAmount, 0, address(this));

        assertEq(received, ybsAmount);
        assertEq(yyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapYbsToYvYyb() public {
        maxApprove(yyb, address(ybs));
        uint256 ybsAmount = IYBS(address(ybs)).stakeFor(address(this), 1000e18);

        uint256 balanceBefore = yvYyb.balanceOf(address(this));

        uint256 received = zap.zap(address(ybs), address(yvYyb), ybsAmount, 0, address(this));

        assertGt(received, 0);
        assertEq(yvYyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_ZapNftToYyb() public {
        uint256 balanceBefore = yyb.balanceOf(address(this));
        uint256 amount = _getLockedAmount(address(this));
        console.log("amount", amount);
        console.log("balance", veYb.balanceOf(address(this)));
        uint256 received = zap.zap(address(veYb), address(yyb), amount, 0, address(this));
        assertGt(received, 0);
        assertEq(yyb.balanceOf(address(this)), balanceBefore + received);
        assertEq(veYb.balanceOf(address(this)), 0);
        assertEq(received, amount);
    }

    function test_ZapRevertsWithZeroAmount() public {
        vm.expectRevert("!amount");
        zap.zap(address(yb), address(yyb), 0, 0, address(this));
    }

    function test_ZapRevertsWithSameInputOutput() public {
        vm.expectRevert("same token");
        zap.zap(address(yyb), address(yyb), 1000e18, 0, address(this));
    }

    function test_ZapRevertsWithInvalidOutput() public {
        vm.expectRevert("invalid output token");
        zap.zap(address(yb), address(0xdead), 1000e18, 0, address(this));
    }

    function test_ZapRevertsWithInvalidInput() public {
        vm.expectRevert("invalid input token");
        zap.zap(address(0xdead), address(yyb), 1000e18, 0, address(this));
    }

    function test_ZapRevertsWithSlippage() public {
        uint256 amount = 1000e18;
        uint256 unrealisticMinOut = 10_000e18;

        vm.expectRevert("slippage");
        zap.zap(address(yb), address(yyb), amount, unrealisticMinOut, address(this));
    }

    function test_ZapWithMaxUint256UsesFullBalance() public {
        uint256 balanceBefore = yyb.balanceOf(address(this));

        uint256 received = zap.zap(address(yb), address(yyb), type(uint256).max, 0, address(this));

        assertGt(received, 0);
        assertEq(yb.balanceOf(address(this)), 0);
        assertEq(yyb.balanceOf(address(this)), balanceBefore + received);
    }

    function test_CalcExpectedOut() view public {
        uint256 amount = 1000e18;
        uint256 expected = zap.calcExpectedOut(address(yb), address(yyb), amount);
        assertGt(expected, 0);
        assertLe(expected, amount);
    }

    function test_CalcExpectedOutReturnsZeroForZeroAmount() view public {
        uint256 expected = zap.calcExpectedOut(address(yb), address(yyb), 0);
        assertEq(expected, 0);
    }

    function test_CalcExpectedOutRevertsForSameToken() public {
        vm.expectRevert("same token");
        zap.calcExpectedOut(address(yyb), address(yyb), 1000e18);
    }

    function test_RelativePrice() view public {
        uint256 amount = 1000e18;
        uint256 price = zap.relativePrice(address(yb), address(yyb), amount);
        assertEq(price, amount);
    }

    function test_RelativePriceReturnsZeroForZeroAmount() view public {
        uint256 price = zap.relativePrice(address(yb), address(yyb), 0);
        assertEq(price, 0);
    }

    function test_RelativePriceReturnsSameForSameToken() view public {
        uint256 amount = 1000e18;
        uint256 price = zap.relativePrice(address(yyb), address(yyb), amount);
        assertEq(price, amount);
    }

    function test_SetMintBuffer() public {
        uint256 newBuffer = 25;

        vm.prank(zap.owner());
        zap.setMintBuffer(newBuffer);

        assertEq(zap.mintBuffer(), newBuffer);
    }

    function test_SetMintBufferRevertsWhenNotOwner() public {
        vm.expectRevert("!owner");
        zap.setMintBuffer(25);
    }

    function test_SetMintBufferRevertsWhenTooHigh() public {
        vm.prank(zap.owner());
        vm.expectRevert("buffer too high");
        zap.setMintBuffer(500);
    }

    function test_Sweep() public {
        deal(address(yb), address(zap), 100e18);
        uint256 balanceBefore = yb.balanceOf(zap.owner());

        vm.prank(zap.owner());
        zap.sweep(address(yb), 100e18);

        assertEq(yb.balanceOf(zap.owner()), balanceBefore + 100e18);
        assertEq(yb.balanceOf(address(zap)), 0);
    }

    function test_SweepWithMaxUint256() public {
        deal(address(yb), address(zap), 100e18);
        uint256 balanceBefore = yb.balanceOf(zap.owner());

        vm.prank(zap.owner());
        zap.sweep(address(yb), type(uint256).max);

        assertEq(yb.balanceOf(zap.owner()), balanceBefore + 100e18);
        assertEq(yb.balanceOf(address(zap)), 0);
    }

    function test_SweepRevertsWhenNotOwner() public {
        vm.expectRevert("!owner");
        zap.sweep(address(yb), 100e18);
    }

    function test_ExhaustiveZapPermutations() public {
        address[] memory tokens = mergedTokens();
        uint256 zapAmount = 1000e18;

        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < tokens.length; j++) {
                if (tokens[i] == tokens[j]) continue;
                if (!zap.isValidInputToken(tokens[i]) || !zap.isValidOutputToken(tokens[j])) continue;
                console.log("Testing zap from %s to %s", tokens[i], tokens[j]);
                uint256 snapshot = vm.snapshot();
                _testZapPermutation(tokens[i], tokens[j], zapAmount);
                vm.revertTo(snapshot);
            }
        }
    }

    function _testZapPermutation(address inputToken, address outputToken, uint256 amount) internal {
        if (inputToken == address(veYb)) amount = _getLockedAmount(address(this));
        uint256 expectedOut = zap.calcExpectedOut(inputToken, outputToken, amount);
        uint256 relPrice = zap.relativePrice(inputToken, outputToken, amount);

        uint256 outputBalanceBefore = IERC20(outputToken).balanceOf(address(this));

        uint256 actualOut = zap.zap(inputToken, outputToken, amount, 0, address(this));

        uint256 actualReceived = IERC20(outputToken).balanceOf(address(this)) - outputBalanceBefore;

        assertEq(actualReceived, actualOut, "Balance mismatch");
        assertApproxEqRel(actualOut, expectedOut, 0.02e18, "Expected vs actual mismatch");
        assertGt(relPrice, 0, "RelativePrice should be > 0");
    }

    function _setYbsApprovedCaller(address owner, address caller) internal {
        vm.prank(owner);
        IYBS(address(ybs)).setApprovedCaller(caller, IYBS.ApprovalStatus.StakeAndUnstake);
    }

    function mergedTokens() public view returns (address[] memory m) {
        address[] memory a = zap.inputTokens();
        address[] memory b = zap.outputTokens();
        address[] memory tmp = new address[](a.length + b.length);
        uint256 n;

        unchecked {
            for (uint256 i; i < a.length; ++i) {
                address x = a[i];
                bool dup;
                for (uint256 k; k < n; ++k) if (tmp[k] == x) { dup = true; break; }
                if (!dup) tmp[n++] = x;
            }
            for (uint256 j; j < b.length; ++j) {
                address x = b[j];
                bool dup;
                for (uint256 k; k < n; ++k) if (tmp[k] == x) { dup = true; break; }
                if (!dup) tmp[n++] = x;
            }
        }

        m = new address[](n);
        for (uint256 i; i < n; ++i) m[i] = tmp[i];
    }

    function _getLockedAmount(address user) internal view returns (uint256) {
        (int256 locked,) = escrow.locked(user);
        return locked > 0 ? uint256(locked) : 0;
    }
}
