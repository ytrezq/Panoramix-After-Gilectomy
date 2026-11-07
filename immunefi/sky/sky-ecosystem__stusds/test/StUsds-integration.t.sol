// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "token-tests/TokenFuzzChecks.sol";
import "dss-interfaces/Interfaces.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { StUsds, UUPSUpgradeable, Initializable, ERC1967Utils } from "src/StUsds.sol";

import { StUsdsInstance } from "deploy/StUsdsInstance.sol";
import { StUsdsDeploy } from "deploy/StUsdsDeploy.sol";
import { StUsdsInit, StUsdsConfig } from "deploy/StUsdsInit.sol";

import { ClipMock } from "test/mocks/ClipMock.sol";

interface UsdsLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external;
}

contract StUsds2 is UUPSUpgradeable {
    // Admin
    mapping (address => uint256) public wards;
    // ERC20
    uint256                                           public totalSupply;
    mapping (address => uint256)                      public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    mapping (address => uint256)                      public nonces;
    // Savings yield
    uint192 public chi;   // The Rate Accumulator  [ray]
    uint64  public rho;   // Time of last drip     [unix epoch time]
    uint256 public str;   // The USDS Savings Rate [ray]

    string  public constant version  = "2";

    event UpgradedTo(string version);

    modifier auth {
        require(wards[msg.sender] == 1, "StUsds/not-authorized");
        _;
    }

    constructor() {
        _disableInitializers(); // Avoid initializing in the context of the implementation
    }

    function reinitialize() reinitializer(2) external {
        emit UpgradedTo(version);
    }

    function _authorizeUpgrade(address newImplementation) internal override auth {}

    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}

contract StUsdsIntegrationTest is TokenFuzzChecks {

    using GodMode for *;

    ChainlogAbstract LOG;

    DssInstance dss;
    address pauseProxy;
    address usdsJoin;
    UsdsLike usds;
    ClipMock clip;

    StUsds token;
    bool validate;

    event Cut(uint256 assets, uint256 oldChi, uint256 newChi);
    event Drip(uint256 chi, uint256 diff);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event Referral(uint16 indexed referral, address indexed owner, uint256 assets, uint256 shares);
    event UpgradedTo(string version);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        validate = vm.envOr("VALIDATE", false);

        LOG = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        dss = MCD.loadFromChainlog(LOG);

        pauseProxy = LOG.getAddress("MCD_PAUSE_PROXY");
        usds = UsdsLike(LOG.getAddress("USDS"));
        usdsJoin = LOG.getAddress("USDS_JOIN");

        clip = new ClipMock("LSEV2-SKY-B");
        StUsdsInstance memory inst = StUsdsDeploy.deploy(address(this), pauseProxy, address(clip));
        token = StUsds(inst.stUsds);
        StUsdsConfig memory conf = StUsdsConfig({
            clip: address(clip),
            str: 1000000001547125957863212448,
            cap: type(uint256).max,
            line: type(uint256).max,
            tau: 0, // passing zeros as RateSetter will not be used in this test
            maxLine: 0,
            maxCap: 0,
            maxDutyBps: 0,
            minDutyBps: 0,
            stepDutyBps: 0,
            maxStrBps: 0,
            minStrBps: 0,
            stepStrBps: 0,
            buds: new address[](0)
        });
        vm.warp(block.timestamp + 10);
        vm.startPrank(pauseProxy);
        dss.vat.file(token.ilk(), "line", 0);
        StUsdsInit.init(dss, inst, conf);
        vm.stopPrank();
        assertEq(token.chi(), RAY);
        assertEq(token.rho(), block.timestamp);
        assertEq(token.str(), 1000000001547125957863212448);
        assertEq(dss.vat.can(address(token), usdsJoin), 1);
        assertEq(token.wards(pauseProxy), 1);
        assertEq(token.version(), "1");
        assertEq(token.getImplementation(), inst.stUsdsImp);

        deal(address(usds), address(this), 200 ether);
        usds.approve(address(token), type(uint256).max);
        token.deposit(100 ether, address(0x222));
    }

    function _rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        assembly {
            switch x case 0 {switch n case 0 {z := RAY} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := RAY } default { z := x }
                let half := div(RAY, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, RAY)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, RAY)
                    }
                }
            }
        }
    }

    function _divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // Note: _divup(0,0) will return 0 differing from natural solidity division
        unchecked {
            z = x != 0 ? ((x - 1) / y) + 1 : 0;
        }
    }

    function _subcap(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x > y ? x - y : 0;
        }
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function testDeployWithUpgradesLib() public {
        address clip2 = address(new ClipMock("LSEV2-SKY-B"));
        Options memory opts;
        if (!validate) {
            opts.unsafeSkipAllChecks = true;
        } else {
            opts.unsafeAllow = 'state-variable-immutable,constructor';
        }
        opts.constructorData = abi.encode(
                                    usdsJoin,
                                    LOG.getAddress("MCD_JUG"),
                                    clip2,
                                    LOG.getAddress("MCD_VOW")
                                    );

        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        address proxy = Upgrades.deployUUPSProxy(
            "out/StUsds.sol/StUsds.json",
            abi.encodeCall(StUsds.initialize, ()),
            opts
        );
        assertEq(StUsds(proxy).version(), "1");
        assertEq(StUsds(proxy).wards(address(this)), 1);
    }

    function testUpgrade() public {
        address implementation1 = token.getImplementation();

        address newImpl = address(new StUsds2());
        vm.startPrank(pauseProxy);
        vm.expectEmit(true, true, true, true);
        emit UpgradedTo("2");
        token.upgradeToAndCall(newImpl, abi.encodeCall(StUsds2.reinitialize, ()));
        vm.stopPrank();

        address implementation2 = token.getImplementation();
        assertEq(implementation2, newImpl);
        assertTrue(implementation2 != implementation1);
        assertEq(token.version(), "2");
        assertEq(token.wards(address(pauseProxy)), 1); // still a ward
    }

    function testUpgradeWithUpgradesLib() public {
        address implementation1 = token.getImplementation();

        Options memory opts;
        if (!validate) {
            opts.unsafeSkipAllChecks = true;
        } else {
            opts.referenceContract = "out/StUsds.sol/StUsds.json";
            opts.unsafeAllow = 'constructor';
        }

        vm.startPrank(pauseProxy);
        vm.expectEmit(true, true, true, true);
        emit UpgradedTo("2");
        Upgrades.upgradeProxy(
            address(token),
            "out/StUsds-integration.t.sol/StUsds2.json",
            abi.encodeCall(StUsds2.reinitialize, ()),
            opts
        );
        vm.stopPrank();

        address implementation2 = token.getImplementation();
        assertTrue(implementation1 != implementation2);
        assertEq(token.version(), "2");
        assertEq(token.wards(address(pauseProxy)), 1); // still a ward
    }

    function testUpgradeUnauthed() public {
        address newImpl = address(new StUsds2());
        vm.expectRevert("StUsds/not-authorized");
        vm.prank(address(0x123)); token.upgradeToAndCall(newImpl, abi.encodeCall(StUsds2.reinitialize, ()));
    }

    function testInitializeAgain() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize();
    }

    function testInitializeDirectly() public {
        address implementation = token.getImplementation();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        StUsds(implementation).initialize();
    }

    function testConstructor() public {
        address clip2 = address(new ClipMock("LSEV2-SKY-B"));
        address imp = address(new StUsds(
                                    usdsJoin,
                                    LOG.getAddress("MCD_JUG"),
                                    clip2,
                                    LOG.getAddress("MCD_VOW")
                                    )
                                );
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        StUsds token2 = StUsds(address(new ERC1967Proxy(imp, abi.encodeCall(StUsds.initialize, ()))));
        assertEq(token2.name(), "Staked USDS");
        assertEq(token2.symbol(), "stUSDS");
        assertEq(token2.version(), "1");
        assertEq(token2.decimals(), 18);
        assertEq(token2.chi(), RAY);
        assertEq(token2.rho(), block.timestamp);
        assertEq(token2.str(), RAY);
        assertEq(dss.vat.can(address(token2), usdsJoin), 1);
        assertEq(token2.wards(address(this)), 1);
        assertEq(address(token2.usdsJoin()), usdsJoin);
        assertEq(address(token2.vat()), address(dss.vat));
        assertEq(address(token2.usds()), address(usds));
        assertEq(address(token2.jug()), LOG.getAddress("MCD_JUG"));
        assertEq(address(token2.clip()), clip2);
        assertEq(address(token2.vow()), LOG.getAddress("MCD_VOW"));
        assertEq(token2.ilk(), "LSEV2-SKY-B");
        assertEq(address(token2.asset()), address(usds));
    }

    function testAuth() public {
        checkAuth(address(token), "StUsds");
    }

    function testFile() public {
        checkFileUint(address(token), "StUsds", ["str"]);

        vm.expectRevert("StUsds/wrong-str-value");
        vm.prank(pauseProxy); token.file("str", RAY - 1);

        vm.warp(block.timestamp + 1);
        vm.expectRevert("StUsds/chi-not-up-to-date");
        vm.prank(pauseProxy); token.file("str", RAY);
    }

    function testERC20() public {
        checkBulkERC20(address(token), "StUsds", "Staked USDS", "stUSDS", "1", 18);
    }

    function testPermit() public {
        checkBulkPermit(address(token), "StUsds");
    }

    function testConversion() public {
        assertGt(token.str(), 0);

        uint256 pshares = token.convertToShares(1e18);
        uint256 passets = token.convertToAssets(pshares);

        // Converting back and forth should always round against
        assertLe(passets, 1e18);

        // Accrue some interest
        vm.warp(block.timestamp + 1 days);

        uint256 shares = token.convertToShares(1e18);

        // Shares should be less because more interest has accrued
        assertLt(shares, pshares);
    }

    uint256 chiFirst;
    uint256 chiMiddle;
    uint256 chiLast;
    uint256 diff1;
    uint256 diff2;
    uint256 diff3;
    uint256 line1;
    uint256 line2;
    uint256 line3;
    uint256 line4;
    uint256 line5;
    uint256 usdsBalanceToken;
    uint256 usdsBalanceFrom;
    uint256 usdsBalanceTo;

    function testDrip() public {
        token.deposit(100 ether, address(this));
        vm.warp(block.timestamp + 100 days);
        (,,, line1,) = dss.vat.ilks(token.ilk());
        uint256 supply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));
        uint256 originalChi = token.chi();
        uint256 expectedChi1 = _rpow(token.str(), block.timestamp - token.rho()) * token.chi() / RAY;
        diff1 = supply * expectedChi1 / RAY - supply * originalChi / RAY;
        vm.expectEmit();
        emit Drip(expectedChi1, diff1);
        assertEq(token.drip(), expectedChi1);
        assertEq(token.chi(), expectedChi1);
        assertGt(diff1, 0);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1);
        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff1 * RAY, 0.00000000000000001e45);
        vm.warp(block.timestamp + 100 days);
        uint256 expectedChi2 = _rpow(token.str(), 100 days) * expectedChi1 / RAY;
        diff2 = supply * expectedChi2 / RAY - supply * expectedChi1 / RAY;
        clip.setDue(1e45);
        vm.expectEmit();
        emit Drip(expectedChi2, diff2);
        assertEq(token.drip(), expectedChi2);
        assertGt(expectedChi2, expectedChi1);
        assertGt(diff2, 0);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + diff2);
        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 + diff2 * RAY - 1e45, 0.00000000000000001e45); // Reduced by ongoing auction debt
        vm.expectEmit();
        emit Drip(expectedChi2, 0);
        assertEq(token.drip(), expectedChi2);
        vm.warp(block.timestamp + 100 days);
        uint256 expectedChi3 = _rpow(token.str(), 100 days) * expectedChi2 / RAY;
        diff3 = supply * expectedChi3 / RAY - supply * expectedChi2 / RAY;
        vm.prank(pauseProxy); token.file("line", line3 + 2e45);
        vm.expectEmit();
        emit Drip(expectedChi3, diff3);
        assertEq(token.drip(), expectedChi3);
        assertGt(expectedChi3, expectedChi2);
        assertGt(diff3 * RAY, 2e45);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + diff2 + diff3);
        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 + 2e45, 0.00000000000000001e45); // Limited by line
        vm.warp(block.timestamp - 1);
        vm.expectEmit();
        emit Drip(expectedChi3, 0);
        assertEq(token.drip(), expectedChi3);
    }

    function testDeposit() public {
        uint256 prevSupply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));

        (,,, line1,) = dss.vat.ilks(token.ilk());

        chiFirst = token.chi();
        chiLast = _rpow(token.str(), 100 days) * chiFirst / RAY;
        assertGt(chiLast, chiFirst);

        vm.warp(block.timestamp + 100 days);

        diff1 = prevSupply * chiLast / RAY - prevSupply * chiFirst / RAY;
        uint256 pie = 1e18 * RAY / chiLast;
        vm.expectEmit();
        emit Drip(chiLast, diff1);
        vm.expectEmit();
        emit Deposit(address(this), address(0xBEEF), 1e18, pie);
        vm.expectEmit();
        emit Transfer(address(0), address(0xBEEF), pie);
        token.deposit(1e18, address(0xBEEF));

        assertEq(token.chi(), chiLast);
        assertEq(token.totalSupply(), prevSupply + pie);
        assertLe(token.totalAssets(), stusdsUsds + diff1 + 1e18);    // May be slightly less due to rounding error
        assertGe(token.totalAssets(), stusdsUsds + diff1 + 1e18 - 1);
        assertEq(token.balanceOf(address(0xBEEF)), pie);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + _divup(pie * chiLast, RAY));
        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff1 * RAY + 1e45, 0.00000000000000001e45);

        token.deposit(1e18, address(0xBEEF));

        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 + 1e45, 0.00000000000000001e45);

        clip.setDue(0.3e45);

        token.deposit(1e18, address(0xBEEF));

        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 + 0.7e45, 0.00000000000000001e45); // Reduced by ongoing auction debt

        vm.prank(pauseProxy); token.file("line", line4 + 0.2e45);

        token.deposit(1e18, address(0xBEEF));

        (,,, line5,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line5, line4 + 0.2e45, 0.00000000000000001e45); // Limited by line
    }

    function testReferredDeposit() public {
        uint256 prevSupply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));

        chiFirst = token.chi();
        chiLast = _rpow(token.str(), 100 days) * chiFirst / RAY;
        assertGt(chiLast, chiFirst);

        vm.warp(block.timestamp + 100 days);

        diff1 = prevSupply * chiLast / RAY - prevSupply * chiFirst / RAY;
        uint256 pie = 1e18 * RAY / chiLast;
        vm.expectEmit();
        emit Drip(chiLast, diff1);
        vm.expectEmit();
        emit Deposit(address(this), address(0xBEEF), 1e18, pie);
        vm.expectEmit();
        emit Transfer(address(0), address(0xBEEF), pie);
        vm.expectEmit();
        emit Referral(888, address(0xBEEF), 1e18, pie);
        token.deposit(1e18, address(0xBEEF), 888);

        assertEq(token.chi(), chiLast);
        assertEq(token.totalSupply(), prevSupply + pie);
        assertLe(token.totalAssets(), stusdsUsds + diff1 + 1e18);    // May be slightly less due to rounding error
        assertGe(token.totalAssets(), stusdsUsds + diff1 + 1e18 - 1);
        assertEq(token.balanceOf(address(0xBEEF)), pie);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + _divup(pie * chiLast, RAY));
    }

    function testDepositBadAddress() public {
        vm.expectRevert("StUsds/invalid-address");
        token.deposit(1e18, address(0));
        vm.expectRevert("StUsds/invalid-address");
        token.deposit(1e18, address(token));
    }

    function testMint() public {
        uint256 prevSupply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));

        (,,, line1,) = dss.vat.ilks(token.ilk());

        chiFirst = token.chi();
        chiLast = _rpow(token.str(), 100 days) * chiFirst / RAY;
        assertGt(chiLast, chiFirst);

        vm.warp(block.timestamp + 100 days);

        diff1 = prevSupply * chiLast / RAY - prevSupply * chiFirst / RAY;
        uint256 pie = 1e18 * RAY / chiLast;
        vm.expectEmit();
        emit Drip(chiLast, diff1);
        vm.expectEmit();
        emit Deposit(address(this), address(0xBEEF), _divup(pie * chiLast, RAY), pie);
        vm.expectEmit();
        emit Transfer(address(0), address(0xBEEF), pie);
        token.mint(pie, address(0xBEEF));

        assertEq(token.chi(), chiLast);
        assertEq(token.totalSupply(), prevSupply + pie);
        assertLe(token.totalAssets(), stusdsUsds + diff1 + 1e18);    // May be slightly less due to rounding error
        assertGe(token.totalAssets(), stusdsUsds + diff1 + 1e18 - 1);
        assertEq(token.balanceOf(address(0xBEEF)), pie);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + _divup(pie * chiLast, RAY));
        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff1 * RAY + 1e45, 0.00000000000000001e45);

        token.mint(pie, address(0xBEEF));

        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 + 1e45, RAY);

        clip.setDue(0.3e45);

        token.mint(pie, address(0xBEEF));

        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 + 0.7e45, 0.00000000000000001e45); // Reduced by ongoing auction debt

        vm.prank(pauseProxy); token.file("line", line4 + 0.2e45);

        token.mint(pie, address(0xBEEF));

        (,,, line5,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line5, line4 + 0.2e45, 0.00000000000000001e45); // Limited by line
    }

    function testReferredMint() public {
        uint256 prevSupply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));

        chiFirst = token.chi();
        chiLast = _rpow(token.str(), 100 days) * chiFirst / RAY;
        assertGt(chiLast, chiFirst);

        vm.warp(block.timestamp + 100 days);

        diff1 = prevSupply * chiLast / RAY - prevSupply * chiFirst / RAY;
        uint256 pie = 1e18 * RAY / chiLast;
        vm.expectEmit();
        emit Drip(chiLast, diff1);
        vm.expectEmit();
        emit Deposit(address(this), address(0xBEEF), _divup(pie * chiLast, RAY), pie);
        vm.expectEmit();
        emit Transfer(address(0), address(0xBEEF), pie);
        vm.expectEmit();
        emit Referral(888, address(0xBEEF), 1e18, pie);
        token.mint(pie, address(0xBEEF), 888);

        assertEq(token.chi(), chiLast);
        assertEq(token.totalSupply(), prevSupply + pie);
        assertLe(token.totalAssets(), stusdsUsds + diff1 + 1e18);    // May be slightly less due to rounding error
        assertGe(token.totalAssets(), stusdsUsds + diff1 + 1e18 - 1);
        assertEq(token.balanceOf(address(0xBEEF)), pie);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + _divup(pie * chiLast, RAY));
    }

    function testMintBadAddress() public {
        vm.expectRevert("StUsds/invalid-address");
        token.mint(1e18, address(0));
        vm.expectRevert("StUsds/invalid-address");
        token.mint(1e18, address(token));
    }

    function testRedeem() public {
        uint256 prevSupply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));

        chiFirst = token.chi();
        chiMiddle = _rpow(token.str(), 100 days) * chiFirst / RAY;
        chiLast = _rpow(token.str(), 200 days) * chiMiddle / RAY;
        assertGt(chiMiddle, chiFirst);
        assertGt(chiLast, chiMiddle);

        vm.warp(block.timestamp + 100 days);

        token.deposit(10e18, address(0xBEEF));
        uint256 pie = 10e18 * RAY / chiMiddle;

        assertEq(token.chi(), chiMiddle);
        diff1 = prevSupply * chiMiddle / RAY - prevSupply * chiFirst / RAY;
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + _divup(pie * chiMiddle, RAY));

        (,,, line1,) = dss.vat.ilks(token.ilk());

        vm.warp(block.timestamp + 200 days);

        vm.expectEmit();
        emit Drip(chiLast, (prevSupply + pie) * chiLast / RAY - (prevSupply + pie) * chiMiddle / RAY);
        vm.expectEmit();
        emit Transfer(address(0xBEEF), address(0), pie * 0.1e18 / WAD);
        vm.expectEmit();
        emit Withdraw(address(0xBEEF), address(0xAAA), address(0xBEEF), (pie * 0.1e18 / WAD) * chiLast / RAY, pie * 0.1e18 / WAD);
        vm.prank(address(0xBEEF)); token.redeem(pie * 0.1e18 / WAD, address(0xAAA), address(0xBEEF));

        diff2 = (prevSupply + pie) * chiLast / RAY - (prevSupply + pie) * chiMiddle / RAY;
        assertEq(token.chi(), chiLast);
        assertEq(token.totalSupply(), prevSupply + pie - pie * 0.1e18 / WAD);
        assertEq(token.balanceOf(address(0xBEEF)), pie - pie * 0.1e18 / WAD);
        assertEq(usds.balanceOf(address(0xAAA)), (pie * 0.1e18 / WAD) * chiLast / RAY);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + diff2 + 10e18 - (pie * 0.1e18 / WAD) * chiLast / RAY);
        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff2 * RAY - (pie * 0.1e18 / WAD) * chiLast, 0.00000000000000001e45);

        vm.prank(address(0xBEEF)); token.redeem(pie * 0.1e18 / WAD, address(0xAAA), address(0xBEEF));

        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 - (pie * 0.1e18 / WAD) * chiLast, 0.00000000000000001e45);

        clip.setDue((pie * 0.05e18 / WAD) * chiLast);

        vm.prank(address(0xBEEF)); token.redeem(pie * 0.1e18 / WAD, address(0xAAA), address(0xBEEF));

        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 - (pie * 0.15e18 / WAD) * chiLast, 0.00000000000000001e45); // Also reduced by ongoing auction debt

        vm.prank(pauseProxy); token.file("line", line4 - (pie * 0.2e18 / WAD) * chiLast);

        vm.prank(address(0xBEEF)); token.redeem(pie * 0.1e18 / WAD, address(0xAAA), address(0xBEEF));

        (,,, line5,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line5, line4 - (pie * 0.2e18 / WAD) * chiLast, 0.00000000000000001e45); // Limited by line

        uint256 rShares = token.balanceOf(address(0xBEEF));
        vm.prank(address(0xBEEF)); token.redeem(rShares, address(0xAAA), address(0xBEEF));
        assertEq(token.totalSupply(), prevSupply);
        assertEq(token.balanceOf(address(0xBEEF)), 0);
        assertEq(usds.balanceOf(address(0xAAA)), pie * chiLast / RAY);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + diff2 + 10e18 - pie * chiLast / RAY);
    }

    function testWithdraw() public {
        uint256 prevSupply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));

        chiFirst = token.chi();
        chiMiddle = _rpow(token.str(), 100 days) * chiFirst / RAY;
        chiLast = _rpow(token.str(), 200 days) * chiMiddle / RAY;
        assertGt(chiMiddle, chiFirst);
        assertGt(chiLast, chiMiddle);

        vm.warp(block.timestamp + 100 days);

        token.deposit(10e18, address(0xBEEF));
        uint256 pie = 10e18 * RAY / chiMiddle;

        assertEq(token.chi(), chiMiddle);
        diff1 = prevSupply * chiMiddle / RAY - prevSupply * chiFirst / RAY;
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + 10e18);

        (,,, line1,) = dss.vat.ilks(token.ilk());

        vm.warp(block.timestamp + 200 days);

        uint256 shares = _divup(2e45, chiLast);
        vm.expectEmit();
        emit Drip(chiLast, (prevSupply + pie) * chiLast / RAY - (prevSupply + pie) * chiMiddle / RAY);
        vm.expectEmit();
        emit Transfer(address(0xBEEF), address(0), shares);
        vm.expectEmit();
        emit Withdraw(address(0xBEEF), address(0xAAA), address(0xBEEF), 2e18, shares);
        vm.prank(address(0xBEEF)); token.withdraw(2e18, address(0xAAA), address(0xBEEF));

        diff2 = (prevSupply + pie) * chiLast / RAY - (prevSupply + pie) * chiMiddle / RAY;
        assertEq(token.chi(), chiLast);
        assertEq(token.totalSupply(), prevSupply + pie - shares);
        assertEq(token.balanceOf(address(0xBEEF)), pie - shares);
        assertEq(usds.balanceOf(address(0xAAA)), 2e18);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + diff2 + 10e18 - 2e18);
        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff2 * RAY - 2e45, 0.00000000000000001e45);

        vm.prank(address(0xBEEF)); token.withdraw(1e18, address(0xAAA), address(0xBEEF));

        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 - 1e45, 0.00000000000000001e45);

        clip.setDue(0.3e45);

        vm.prank(address(0xBEEF)); token.withdraw(1e18, address(0xAAA), address(0xBEEF));

        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 - 1.3e45, 0.00000000000000001e45); // Also reduced by ongoing auction debt

        vm.prank(pauseProxy); token.file("line", line4 - 2e45);

        vm.prank(address(0xBEEF)); token.withdraw(1e18, address(0xAAA), address(0xBEEF));

        (,,, line5,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line5, line4 - 2e45, 0.00000000000000001e45); // Limited by line

        uint256 rAssets = token.balanceOf(address(0xBEEF)) * chiLast / RAY;
        vm.prank(address(0xBEEF));
        token.withdraw(rAssets, address(0xAAA), address(0xBEEF));
        assertEq(token.totalSupply(), prevSupply);
        assertEq(token.balanceOf(address(0xBEEF)), 0);
        assertEq(usds.balanceOf(address(0xAAA)), 5e18 + rAssets);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + diff2 + 10e18 - 5e18 - rAssets);
    }

    function testSharesEstimatesMatch() public {
        vm.warp(block.timestamp + 365 days);

        uint256 assets = 1e18;
        uint256 shares = token.convertToShares(assets);

        token.drip();

        assertEq(token.convertToShares(assets), shares);
    }

    function testAssetsEstimatesMatch() public {
        vm.warp(block.timestamp + 365 days);

        uint256 shares = 1e18;
        uint256 assets = token.convertToAssets(shares);

        token.drip();

        assertEq(token.convertToAssets(shares), assets);
    }

    function testERC20Fuzz(
        address from,
        address to,
        uint256 amount1,
        uint256 amount2
    ) public {
        checkBulkERC20Fuzz(address(token), "StUsds", from, to, amount1, amount2);
    }

    function testPermitFuzz(
        uint128 privKey,
        address to,
        uint256 amount,
        uint256 deadline,
        uint256 nonce
    ) public {
        checkBulkPermitFuzz(address(token), "StUsds", privKey, to, amount, deadline, nonce);
    }

    function testDrip(uint256 amount, uint256 warp, uint256 warp2, uint256 warp3, uint256 due, uint256 line) public {
        warp = bound(warp, 1, 365 days);
        warp2 = bound(warp2, 1, 365 days);
        warp3 = bound(warp3, 1, 365 days);
        amount = bound(amount, 0, 100 ether);
        token.deposit(amount, address(this));
        vm.warp(block.timestamp + warp);
        (,,, line1,) = dss.vat.ilks(token.ilk());
        uint256 supply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));
        uint256 originalChi = token.chi();
        uint256 expectedChi1 = _rpow(token.str(), block.timestamp - token.rho()) * token.chi() / RAY;
        diff1 = supply * expectedChi1 / RAY - supply * originalChi / RAY;
        vm.expectEmit();
        emit Drip(expectedChi1, diff1);
        assertEq(token.drip(), expectedChi1);
        assertEq(token.chi(), expectedChi1);
        assertGt(diff1, 0);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1);
        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff1 * RAY, 0.00000000000000001e45);
        vm.warp(block.timestamp + warp2);
        uint256 expectedChi2 = _rpow(token.str(), warp2) * expectedChi1 / RAY;
        diff2 = supply * expectedChi2 / RAY - supply * expectedChi1 / RAY;
        due = bound(due, 0, _min(line2 + diff2 * RAY, supply * expectedChi2));
        clip.setDue(due);
        vm.expectEmit();
        emit Drip(expectedChi2, diff2);
        assertEq(token.drip(), expectedChi2);
        assertGt(expectedChi2, expectedChi1);
        assertGt(diff2, 0);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + diff2);
        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 + diff2 * RAY - due, 0.00000000000000001e45); // Reduced by ongoing auction debt
        vm.expectEmit();
        emit Drip(expectedChi2, 0);
        assertEq(token.drip(), expectedChi2);
        vm.warp(block.timestamp + warp3);
        uint256 expectedChi3 = _rpow(token.str(), warp3) * expectedChi2 / RAY;
        diff3 = supply * expectedChi3 / RAY - supply * expectedChi2 / RAY;
        line = bound(line, 0, diff3 * RAY);
        vm.prank(pauseProxy); token.file("line", line3 + line);
        vm.expectEmit();
        emit Drip(expectedChi3, diff3);
        assertEq(token.drip(), expectedChi3);
        assertGt(expectedChi3, expectedChi2);
        assertGe(diff3 * RAY, line);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + diff2 + diff3);
        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 + line, 0.00000000000000001e45); // Limited by line
        vm.warp(block.timestamp - 1);
        vm.expectEmit();
        emit Drip(expectedChi3, 0);
        assertEq(token.drip(), expectedChi3);
    }

    function testDeposit(
        address to,
        uint256 amount,
        uint256 amount2,
        uint256 amount3,
        uint256 amount4,
        uint256 warp,
        uint256 due,
        uint256 line
    ) public {
        vm.assume(to != address(0x222));
        amount  = bound(amount,  1, 100 ether);
        amount2 = bound(amount2, 1, 100 ether);
        amount3 = bound(amount3, 1, 100 ether);
        amount4 = bound(amount4, 1, 100 ether);
        warp = bound(warp, 0, 365 days);

        deal(address(usds), address(this), 400 ether);

        uint256 prevSupply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));

        (,,, line1,) = dss.vat.ilks(token.ilk());

        chiFirst = token.chi();
        chiLast = _rpow(token.str(), warp) * chiFirst / RAY;
        assertGe(chiLast, chiFirst);

        vm.warp(block.timestamp + warp);

        uint256 shares = token.previewDeposit(amount);
        if (to != address(0) && to != address(token)) {
            diff1 = prevSupply * chiLast / RAY - prevSupply * chiFirst / RAY;

            vm.expectEmit();
            emit Drip(chiLast, diff1);
            vm.expectEmit();
            emit Deposit(address(this), to, amount, shares);
            vm.expectEmit();
            emit Transfer(address(0), to, shares);
            uint256 ashares = token.deposit(amount, to);

            assertEq(token.chi(), chiLast);
            assertEq(ashares, shares);
            assertEq(token.totalSupply(), prevSupply + shares);
            assertEq(token.balanceOf(to), shares);
            assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + amount);

            (,,, line2,) = dss.vat.ilks(token.ilk());
            assertApproxEqAbs(line2, line1 + (diff1 + amount) * RAY, 0.00000000000000001e45);

            token.deposit(amount2, address(0xBEEF));
            (,,, line3,) = dss.vat.ilks(token.ilk());
            assertApproxEqAbs(line3, line2 + amount2 * RAY, 0.00000000000000001e45);

            uint256 totalAssets = (token.totalSupply() + token.previewDeposit(amount3)) * chiLast;
            due = bound(due, 0, _min(line3 + amount3 * RAY, totalAssets));
            clip.setDue(due);

            token.deposit(amount3, address(0xBEEF));

            (,,, line4,) = dss.vat.ilks(token.ilk());
            assertApproxEqAbs(line4, line3 + amount3 * RAY - due, 0.00000000000000001e45); // Reduced by ongoing auction debt

            line = bound(line, 0, amount4 * RAY);
            vm.prank(pauseProxy); token.file("line", line4 + line);

            token.deposit(amount4, address(0xBEEF));

            (,,, line5,) = dss.vat.ilks(token.ilk());
            assertApproxEqAbs(line5, line4 + line, 0.00000000000000001e45); // Limited by line
        } else {
            vm.expectRevert("StUsds/invalid-address");
            token.deposit(amount, to);
        }
    }

    function testMint(
        address to,
        uint256 shares,
        uint256 shares2,
        uint256 shares3,
        uint256 shares4,
        uint256 warp,
        uint256 due,
        uint256 line
    ) public {
        vm.assume(to != address(0x222));
        shares  = bound(shares,  1, 100 ether);
        shares2 = bound(shares2, 1, 100 ether);
        shares3 = bound(shares3, 1, 100 ether);
        shares4 = bound(shares4, 1, 100 ether);
        warp = bound(warp, 0, 365 days);

        deal(address(usds), address(this), 10_000 ether);

        vm.warp(block.timestamp + warp);

        uint256 prevSupply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));

        (,,, line1,) = dss.vat.ilks(token.ilk());

        chiFirst = token.chi();
        chiLast = _rpow(token.str(), warp) * chiFirst / RAY;
        assertGe(chiLast, chiFirst);

        shares = bound(shares, 0, 100 ether * RAY / chiLast);

        uint256 assets = token.previewMint(shares);
        if (to != address(0) && to != address(token)) {
            diff1 = prevSupply * chiLast / RAY - prevSupply * chiFirst / RAY;

            vm.expectEmit();
            emit Drip(chiLast, diff1);
            vm.expectEmit();
            emit Deposit(address(this), to, assets, shares);
            vm.expectEmit();
            emit Transfer(address(0), to, shares);
            uint256 aassets = token.mint(shares, to);

            assertEq(token.chi(), chiLast);
            assertEq(aassets, assets);
            assertEq(token.totalSupply(), prevSupply + shares);
            assertEq(token.balanceOf(to), shares);
            assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 + _divup(shares * chiLast, RAY));

            (,,, line2,) = dss.vat.ilks(token.ilk());
            assertApproxEqAbs(line2, line1 + diff1 * RAY + shares * chiLast, 0.00000000000000001e45);

            token.mint(shares2, address(0xBEEF));
            (,,, line3,) = dss.vat.ilks(token.ilk());
            assertApproxEqAbs(line3, line2 + shares2 * chiLast, 0.00000000000000001e45);

            due = bound(due, 0, line3 + shares3 * chiLast);
            clip.setDue(due);

            token.mint(shares3, address(0xBEEF));

            (,,, line4,) = dss.vat.ilks(token.ilk());
            assertApproxEqAbs(line4, line3 + shares3 * chiLast - due, 0.00000000000000001e45); // Reduced by ongoing auction debt

            line = bound(line, 0, shares4 * chiLast);
            vm.prank(pauseProxy); token.file("line", line4 + line);

            token.mint(shares4, address(0xBEEF));

            (,,, line5,) = dss.vat.ilks(token.ilk());
            assertApproxEqAbs(line5, line4 + line, 0.00000000000000001e45); // Limited by line
        } else {
            vm.expectRevert("StUsds/invalid-address");
            token.mint(shares, to);
        }
    }

    function testRedeem(
        address from,
        address to,
        uint256 redeemAmount,
        uint256 warp,
        uint256 warp2,
        uint256 due,
        uint256 line
    ) public {
        vm.assume(from != address(0) && from != address(token) && from != address(0x222));
        vm.assume(to != address(0) && to != address(token) && to != address(usds) && to != address(0x222));
        redeemAmount = bound(redeemAmount, 1, 100 ether);

        warp = bound(warp, 0, 365 days);
        warp2 = bound(warp2, 0, 365 days);

        uint256 prevSupply = token.totalSupply();
        usdsBalanceToken = usds.balanceOf(address(token));
        usdsBalanceFrom = usds.balanceOf(from);
        usdsBalanceTo = usds.balanceOf(to);
        chiFirst = token.chi();
        chiMiddle = _rpow(token.str(), warp) * chiFirst / RAY;
        chiLast = _rpow(token.str(), warp2) * chiMiddle / RAY;
        assertGe(chiMiddle, chiFirst);
        assertGe(chiLast, chiMiddle);

        vm.warp(block.timestamp + warp);

        uint256 depositAmount = redeemAmount * 4 * chiLast * 2 / RAY;
        uint256 pie = token.convertToShares(depositAmount);

        deal(address(usds), address(0x222), depositAmount);
        vm.startPrank(address(0x222));
        usds.approve(address(token), depositAmount);
        token.deposit(depositAmount, from);
        vm.stopPrank();

        assertEq(token.chi(), chiMiddle);
        diff1 = prevSupply * chiMiddle / RAY - prevSupply * chiFirst / RAY;
        assertEq(usds.balanceOf(address(token)), usdsBalanceToken + diff1 + depositAmount);

        (,,, line1,) = dss.vat.ilks(token.ilk());

        vm.warp(block.timestamp + warp2);

        vm.expectEmit();
        emit Drip(chiLast, (prevSupply + pie) * chiLast / RAY - (prevSupply + pie) * chiMiddle / RAY);
        vm.expectEmit();
        emit Transfer(from, address(0), redeemAmount);
        vm.expectEmit();
        emit Withdraw(from, to, from, redeemAmount * chiLast / RAY, redeemAmount);
        vm.prank(from); assertEq(token.redeem(redeemAmount, to, from), redeemAmount * chiLast / RAY);

        diff2 = (prevSupply + pie) * chiLast / RAY - (prevSupply + pie) * chiMiddle / RAY;
        assertEq(token.chi(), chiLast);
        uint256 shares = _divup(redeemAmount * chiLast / RAY * RAY, chiLast);
        assertEq(token.totalSupply(), prevSupply + pie - shares);
        assertEq(token.balanceOf(from), pie - shares);
        if (from != to) assertEq(usds.balanceOf(from), usdsBalanceFrom);
        assertEq(usds.balanceOf(to), usdsBalanceTo + redeemAmount * chiLast / RAY);
        assertEq(usds.balanceOf(address(token)), usdsBalanceToken + diff1 + diff2 + depositAmount - redeemAmount * chiLast / RAY);
        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff2 * RAY - redeemAmount * chiLast, 0.00000000000000001e45);

        vm.prank(from); token.redeem(redeemAmount, to, from);

        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 - redeemAmount * chiLast, 0.00000000000000001e45);

        due = bound(due, 0, redeemAmount * chiLast);
        clip.setDue(due);

        vm.prank(from); token.redeem(redeemAmount, to, from);

        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 - redeemAmount * chiLast - due, 0.00000000000000001e45); // Also reduced by ongoing auction debt

        line = bound(line, 0, redeemAmount * chiLast);
        vm.prank(pauseProxy); token.file("line", line4 - redeemAmount * chiLast - line);

        vm.prank(from); token.redeem(redeemAmount, to, from);

        (,,, line5,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line5, line, line4 - redeemAmount * chiLast - line); // Limited by line

        vm.prank(from); token.redeem(pie - 4 * redeemAmount, to, from);
        assertEq(token.totalSupply(), prevSupply);
        assertEq(token.balanceOf(from), 0);
        if (from != to) assertEq(usds.balanceOf(from), usdsBalanceFrom);
        assertEq(usds.balanceOf(to), usdsBalanceTo + 4 * (redeemAmount * chiLast / RAY) + (pie - 4 * redeemAmount) * chiLast / RAY);
        assertEq(usds.balanceOf(address(token)), usdsBalanceToken + diff1 + diff2 + depositAmount - 4 * (redeemAmount * chiLast / RAY) - (pie - 4 * redeemAmount) * chiLast / RAY);
    }

    function testWithdraw(
        address from,
        address to,
        uint256 withdrawAmount,
        uint256 warp,
        uint256 warp2,
        uint256 due,
        uint256 line
    ) public {
        vm.assume(from != address(0) && from != address(token) && from != address(0x222));
        vm.assume(to != address(0) && to != address(token) && to != address(usds) && to != address(0x222));
        withdrawAmount = bound(withdrawAmount, 1, 100 ether);

        warp = bound(warp, 0, 365 days);
        warp2 = bound(warp2, 0, 365 days);

        uint256 prevSupply = token.totalSupply();
        usdsBalanceToken = usds.balanceOf(address(token));
        usdsBalanceFrom = usds.balanceOf(from);
        usdsBalanceTo = usds.balanceOf(to);
        chiFirst = token.chi();
        chiMiddle = _rpow(token.str(), warp) * chiFirst / RAY;
        chiLast = _rpow(token.str(), warp2) * chiMiddle / RAY;
        assertGe(chiMiddle, chiFirst);
        assertGe(chiLast, chiMiddle);

        vm.warp(block.timestamp + warp);

        uint256 depositAmount = withdrawAmount * 4 * 2;
        uint256 pie = token.convertToShares(depositAmount);

        deal(address(usds), address(0x222), depositAmount);
        vm.startPrank(address(0x222));
        usds.approve(address(token), depositAmount);
        token.deposit(depositAmount, from);
        vm.stopPrank();

        assertEq(token.chi(), chiMiddle);
        diff1 = prevSupply * chiMiddle / RAY - prevSupply * chiFirst / RAY;
        assertEq(usds.balanceOf(address(token)), usdsBalanceToken + diff1 + depositAmount);

        (,,, line1,) = dss.vat.ilks(token.ilk());

        vm.warp(block.timestamp + warp2);

        uint256 shares = token.previewWithdraw(withdrawAmount);
        vm.expectEmit();
        emit Drip(chiLast, (prevSupply + pie) * chiLast / RAY - (prevSupply + pie) * chiMiddle / RAY);
        vm.expectEmit();
        emit Transfer(from, address(0), shares);
        vm.expectEmit();
        emit Withdraw(from, to, from, withdrawAmount, shares);
        vm.prank(from);
        assertEq(token.withdraw(withdrawAmount, to, from), shares);

        diff2 = (prevSupply + pie) * chiLast / RAY - (prevSupply + pie) * chiMiddle / RAY;
        assertEq(token.chi(), chiLast);
        assertEq(token.totalSupply(), prevSupply + pie - shares);
        assertEq(token.balanceOf(from), pie - shares);
        if (from != to) assertEq(usds.balanceOf(from), usdsBalanceFrom);
        assertEq(usds.balanceOf(to), usdsBalanceTo + withdrawAmount);
        assertEq(usds.balanceOf(address(token)), usdsBalanceToken + diff1 + diff2 + depositAmount - withdrawAmount);
        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff2 * RAY - withdrawAmount * RAY, 0.00000000000000001e45);

        vm.prank(from); token.withdraw(withdrawAmount, to, from);

        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 - withdrawAmount * RAY, 0.00000000000000001e45);

        due = bound(due, 0, withdrawAmount * RAY);
        clip.setDue(due);

        vm.prank(from); token.withdraw(withdrawAmount, to, from);

        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 - withdrawAmount * RAY - due, 0.00000000000000001e45); // Also reduced by ongoing auction debt

        line = bound(line, 0, withdrawAmount * RAY);
        vm.prank(pauseProxy); token.file("line", line4 - withdrawAmount * RAY - line);

        vm.prank(from); token.withdraw(withdrawAmount, to, from);

        (,,, line5,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line5, line4 - withdrawAmount * RAY - line, 0.00000000000000001e45); // Limited by line

        uint256 rAssets = token.balanceOf(from) * chiLast / RAY;
        vm.prank(from);
        token.withdraw(rAssets, to, from);
        assertEq(token.totalSupply(), prevSupply);
        assertEq(token.balanceOf(from), 0);
        if (from != to) assertEq(usds.balanceOf(from), usdsBalanceFrom);
        assertEq(usds.balanceOf(to), usdsBalanceTo + 4 * withdrawAmount + rAssets);
        assertEq(usds.balanceOf(address(token)), usdsBalanceToken + diff1 + diff2 + depositAmount - 4 * withdrawAmount - rAssets);
    }

    function testMaxDepositMint(
        uint256 cap,
        uint256 depositAmount,
        uint256 warp
    ) public {
        cap = bound(cap, 2_000 ether, 1_000_000 ether);
        vm.prank(pauseProxy); token.file("cap", cap);

        warp = bound(warp, 0, 10 days);

        chiLast = ((block.timestamp + warp) > token.rho()) ? _rpow(token.str(), (block.timestamp + warp) - token.rho()) * token.chi() / RAY : token.chi();

        depositAmount = bound(depositAmount, 0, _subcap(cap, token.totalSupply() * chiLast));
        depositAmount = depositAmount * token.chi() / chiLast;

        deal(address(usds), address(this), 100_000_000 ether);
        usds.approve(address(token), 100_000_000 ether);
        token.deposit(depositAmount, address(this));

        vm.warp(block.timestamp + warp);

        uint256 maxDeposit = token.maxDeposit(address(0));
        uint256 maxMint = token.maxMint(address(0));

        assertEq(maxDeposit, _subcap(token.cap(), token.totalAssets()));
        assertEq(maxMint, _subcap(token.cap(), token.totalAssets()) * RAY / chiLast);

        vm.expectRevert("StUsds/mint-over-supply-cap");
        token.deposit(maxDeposit + 1, address(this));

        vm.expectRevert("StUsds/mint-over-supply-cap");
        token.mint(maxMint + 1, address(this));

        uint256 id = vm.snapshot();

        token.deposit(maxDeposit, address(this));
        assertLe(token.maxDeposit(address(0)), 1);
        assertEq(token.maxMint(address(0)), 0);

        vm.revertTo(id);

        token.mint(maxMint, address(this));
        assertLe(token.maxDeposit(address(this)), 1);
        assertEq(token.maxMint(address(this)), 0);

        vm.prank(pauseProxy); token.file("cap", type(uint256).max);
        assertEq(token.maxDeposit(address(0)), type(uint256).max);
        assertEq(token.maxMint(address(0)), type(uint256).max);
    }

    function testMaxWithdrawRedeem(
        uint256 depositAmount,
        uint256 rate,
        uint256 due,
        uint256 div1,
        uint256 div2
    ) public {
        depositAmount = bound(depositAmount, 2_000 ether, 1_000_000 ether);

        deal(address(usds), address(this), depositAmount);
        usds.approve(address(token), depositAmount);
        token.deposit(depositAmount, address(0x222));

        rate = bound(rate, RAY, 2 * RAY);

        vm.startPrank(pauseProxy);
        dss.vat.file(token.ilk(), "spot", RAY);
        dss.vat.slip(token.ilk(), address(this), int256(depositAmount));
        dss.jug.init(token.ilk());
        dss.vat.fold(token.ilk(), address(0), int256(rate));
        vm.stopPrank();

        div1 = bound(div1, 2, 10);
        div2 = bound(div2, 2, 10);

        uint256 maxWithdraw1 = token.maxWithdraw(address(0x222));
        uint256 maxRedeem1 = token.maxRedeem(address(0x222));

        assertEq(maxWithdraw1, token.convertToAssets(token.balanceOf(address(0x222))));
        assertEq(maxRedeem1, token.balanceOf(address(0x222)));

        vm.expectRevert("StUsds/insufficient-balance");
        vm.prank(address(0x222)); token.withdraw(maxWithdraw1 + 1, address(0x222), address(0x222));

        vm.expectRevert("StUsds/insufficient-balance");
        vm.prank(address(0x222)); token.redeem(maxRedeem1 + 1, address(0x222), address(0x222));

        uint256 id = vm.snapshot();

        vm.prank(address(0x222)); token.withdraw(maxWithdraw1, address(0x222), address(0x222));
        assertEq(token.maxWithdraw(address(0x222)), 0);
        assertEq(token.maxRedeem(address(0x222)), 0);

        vm.revertTo(id);

        vm.prank(address(0x222)); token.redeem(maxRedeem1, address(0x222), address(0x222));
        assertEq(token.maxWithdraw(address(0x222)), 0);
        assertEq(token.maxRedeem(address(0x222)), 0);

        vm.revertTo(id);

        uint256 art = depositAmount * RAY / (rate * div1);
        dss.vat.frob(token.ilk(), address(this), address(this), address(this), int256(depositAmount), int256(art));

        due = bound(due, 100 ether, depositAmount * RAY / div2);
        clip.setDue(due);

        uint256 chi = token.chi();
        uint256 totalAssetsRAD = token.balanceOf(address(0x222)) * chi;
        assertEq(totalAssetsRAD / RAY, depositAmount + 100 ether);

        uint256 maxWithdraw2 = token.maxWithdraw(address(0x222));
        uint256 maxRedeem2 = token.maxRedeem(address(0x222));

        assertLt(maxWithdraw2, maxWithdraw1);
        assertLt(maxRedeem2, maxRedeem1);

        vm.expectRevert("StUsds/insufficient-unused-funds");
        vm.prank(address(0x222)); token.withdraw(maxWithdraw2 + 1, address(0x222), address(0x222));

        vm.expectRevert("StUsds/insufficient-unused-funds");
        vm.prank(address(0x222)); token.redeem(maxRedeem2 + 1, address(0x222), address(0x222));

        id = vm.snapshot();

        vm.prank(address(0x222)); token.withdraw(maxWithdraw2, address(0x222), address(0x222));
        assertEq(token.maxWithdraw(address(0x222)), 0);
        assertEq(token.maxRedeem(address(0x222)), 0);

        vm.revertTo(id);

        vm.prank(address(0x222)); token.redeem(maxRedeem2, address(0x222), address(0x222));
        assertEq(token.maxWithdraw(address(0x222)), 0);
        assertEq(token.maxRedeem(address(0x222)), 0);
    }

    function testRedeemInsufficientBalance(
        address to,
        uint256 mintAmount,
        uint256 burnAmount
    ) public {
        vm.assume(to != address(0) && to != address(token) && to != address(usds) && to != address(0x222));
        mintAmount = bound(mintAmount, 0, 100 ether);

        uint256 pie = mintAmount * RAY / token.chi();
        burnAmount = bound(burnAmount, pie + 1, type(uint256).max / token.chi());

        token.deposit(mintAmount, to);
        vm.expectRevert("StUsds/insufficient-balance");
        token.redeem(burnAmount, to, to);
    }

    function testCut() public {
        deal(address(usds), address(this), 10_000e18);
        usds.approve(address(token), 10_000e18);
        token.deposit(10_000e18, address(this));

        (,,, line1,) = dss.vat.ilks(token.ilk());
        uint256 supply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));
        uint256 totalAssets = token.totalAssets();
        uint256 vatDaiVow = dss.vat.dai(address(dss.vow));
        assertLe(totalAssets, stusdsUsds);
        chiFirst = token.chi();
        uint256 chiPrevDeduction = _rpow(token.str(), block.timestamp + 100 days - token.rho()) * token.chi() / RAY;
        diff1 = supply * chiPrevDeduction / RAY - supply * chiFirst / RAY;
        chiLast = chiPrevDeduction * (totalAssets + diff1 - 1_000e18) / (totalAssets + diff1);

        vm.warp(block.timestamp + 100 days);

        vm.expectEmit();
        emit Cut(1_000e18, chiPrevDeduction, chiLast);
        vm.prank(pauseProxy); token.cut(1_000e45);

        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff1 * RAY - 1_000e45, 0.00000000000000001e45);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 - 1_000e18);
        assertEq(token.chi(), chiLast);
        assertEq(dss.vat.dai(address(dss.vow)), vatDaiVow + 1_000e45);

        clip.setDue(300e18);

        vm.prank(pauseProxy); token.cut(1_000e45);

        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 - 1_000e45 - 300e18, 0.00000000000000001e45); // Also reduced by ongoing auction debt

        vm.prank(pauseProxy); token.file("line", line3 - 1_000e45 - 500e45);

        vm.prank(pauseProxy); token.cut(1_000e45);

        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 - 1_000e45 - 500e45, 0.00000000000000001e45); // Limited by line
    }

    function testCutChiMinimal() public {
        // Extreme case where almost everything is cut but the very minimal chi remains.
        // New deposits should still preserve value.
        deal(address(usds), address(this), 999_999_950e18);
        token.deposit(999_999_900e18, address(0x222));

        assertEq(token.chi(), 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0x222)), 1e27);
        assertEq(token.convertToAssets(token.balanceOf(address(this))), 0);
        assertEq(token.convertToAssets(token.balanceOf(address(0x222))), 1e27);
        assertEq(token.totalAssets(), 1e27);

        vm.expectEmit();
        emit Cut(1e27 - 1, 1e27, 1);
        vm.prank(pauseProxy); token.cut((1e27 - 1) * 1e27);

        assertEq(token.chi(), 1);
        assertEq(token.convertToAssets(token.balanceOf(address(this))), 0);
        assertEq(token.convertToAssets(token.balanceOf(address(0x222))), 1);
        assertEq(token.totalAssets(), 1);

        token.deposit(50e18, address(this));

        assertEq(token.totalSupply(), 50e45 + 1e27);
        assertEq(token.balanceOf(address(this)), 50e45);
        assertEq(token.balanceOf(address(0x222)), 1e27);
        assertEq(token.convertToAssets(token.balanceOf(address(this))), 50e18);
        assertEq(token.convertToAssets(token.balanceOf(address(0x222))), 1);
        assertEq(token.totalAssets(), 50e18 + 1);
    }

    function testCutChiZero() public {
        // Extreme case where everything is cut making chi zero.
        // New deposits are forbidden as there isn't any more value in the system.
        deal(address(usds), address(this), 999_999_950e18);
        token.deposit(999_999_900e18, address(0x222));

        assertEq(token.chi(), 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0x222)), 1e27);
        assertEq(token.convertToAssets(token.balanceOf(address(this))), 0);
        assertEq(token.convertToAssets(token.balanceOf(address(0x222))), 1e27);
        assertEq(token.totalAssets(), 1e27);

        uint256 id = vm.snapshot();

        vm.expectEmit();
        emit Cut(1e27, 1e27, 0);
        vm.prank(pauseProxy); token.cut(1e27 * 1e27);

        vm.revertTo(id);

        vm.expectEmit();
        emit Cut(1e27, 1e27, 0);
        vm.prank(pauseProxy); token.cut(2e27 * 1e27);

        assertEq(token.chi(), 0);
        assertEq(token.convertToAssets(token.balanceOf(address(this))), 0);
        assertEq(token.convertToAssets(token.balanceOf(address(0x222))), 0);
        assertEq(token.totalAssets(), 0);

        assertEq(token.convertToShares(1e18), 0);
        assertEq(token.convertToAssets(1e18), 0);
        assertEq(token.maxDeposit(address(0)), 0);
        assertEq(token.previewDeposit(1e18), 0);
        assertEq(token.maxMint(address(0)), 0);
        assertEq(token.previewMint(1e18), 0);
        assertEq(token.maxWithdraw(address(0x222)), 0);
        assertEq(token.previewWithdraw(1e18), 0);
        assertEq(token.maxRedeem(address(0x222)), 0);
        assertEq(token.previewRedeem(1e18), 0);

        vm.expectRevert(stdError.divisionError);
        token.deposit(50e18, address(this));
        vm.expectRevert("StUsds/assets-zero");
        token.mint(50e18, address(this));
        vm.expectRevert(stdError.divisionError);
        vm.prank(address(0x222)); token.withdraw(1, address(this), address(this));
        vm.expectRevert("StUsds/assets-zero");
        vm.prank(address(0x222)); token.redeem(1, address(this), address(this));
    }

    function testCutChiZeroDueRounding() public {
        // Extreme case where almost everything is cut and due to rounding chi ends up being zero.
        // New deposits are forbidden as there isn't any more value in the system.
        vm.prank(pauseProxy); dss.vat.suck(address(0), usdsJoin, 10_000_000_000e45);
        deal(address(usds), address(this), 9_999_999_950e18);
        token.deposit(9_999_999_900e18, address(0x222));

        assertEq(token.chi(), 1e27);
        assertEq(token.totalSupply(), 10e27);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0x222)), 10e27);
        assertEq(token.convertToAssets(token.balanceOf(address(this))), 0);
        assertEq(token.convertToAssets(token.balanceOf(address(0x222))), 10e27);
        assertEq(token.totalAssets(), 10e27);

        vm.expectEmit();
        emit Cut(10e27 - 1, 1e27, 0);
        vm.prank(pauseProxy); token.cut((10e27 - 1) * 1e27);

        assertEq(token.chi(), 0);
        assertEq(token.convertToAssets(token.balanceOf(address(this))), 0);
        assertEq(token.convertToAssets(token.balanceOf(address(0x222))), 0);
        assertEq(token.totalAssets(), 0);

        vm.expectRevert(stdError.divisionError);
        token.deposit(50e18, address(this));
        vm.expectRevert("StUsds/assets-zero");
        token.mint(50e18, address(this));
    }

    function testCutAfterZeroAssets() public {
        assertEq(token.totalAssets(), 100e18);

        // Proving that even without assets second cut call won't fail.
        // This is important to make sure any auction shouldn't revert even if stusds gets to irreversible state
        vm.expectEmit();
        emit Cut(100e18, 1e27, 0);
        vm.prank(pauseProxy); token.cut(100e18 * 1e27);
        assertEq(token.totalAssets(), 0);
        assertEq(token.chi(), 0);
        emit Cut(0, 0, 0);
        vm.prank(pauseProxy); token.cut(1 * 1e27);
    }

    function testCut(
        uint256 depositAmount,
        uint256 warp,
        uint256 rad,
        uint256 due,
        uint256 line
    ) public {
        depositAmount = bound(depositAmount, 1_000 ether, 1_000_000 ether);
        warp = bound(warp, 0, 365 days);
        rad = bound(rad, 0, depositAmount * RAY / 5);

        uint256 assets = _divup(rad, RAY);

        deal(address(usds), address(this), depositAmount);
        usds.approve(address(token), depositAmount);
        token.deposit(depositAmount, address(this));

        (,,, line1,) = dss.vat.ilks(token.ilk());
        uint256 supply = token.totalSupply();
        uint256 stusdsUsds = usds.balanceOf(address(token));
        uint256 totalAssets = token.totalAssets();
        uint256 vatDaiVow = dss.vat.dai(address(dss.vow));
        assertLe(totalAssets, stusdsUsds);
        chiFirst = token.chi();
        uint256 chiPrevDeduction = _rpow(token.str(), block.timestamp + warp - token.rho()) * token.chi() / RAY;
        diff1 = supply * chiPrevDeduction / RAY - supply * chiFirst / RAY;
        chiLast = chiPrevDeduction * (totalAssets + diff1 - assets) / (totalAssets + diff1);

        vm.warp(block.timestamp + warp);

        vm.expectEmit();
        emit Cut(_divup(rad, RAY), chiPrevDeduction, chiLast);
        vm.prank(pauseProxy); token.cut(rad);

        (,,, line2,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line2, line1 + diff1 * RAY - assets * RAY, 0.00000000000000001e45);
        assertEq(usds.balanceOf(address(token)), stusdsUsds + diff1 - assets);
        assertEq(token.chi(), chiLast);
        assertEq(dss.vat.dai(address(dss.vow)), vatDaiVow + assets * RAY);

        due = bound(due, 0, assets * RAY);
        clip.setDue(due);

        vm.prank(pauseProxy); token.cut(rad);

        (,,, line3,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line3, line2 - assets * RAY - due, 0.00000000000000001e45); // Also reduced by ongoing auction debt

        line = bound(line, 0, assets * RAY);
        vm.prank(pauseProxy); token.file("line", line3 - assets * RAY - line);

        vm.prank(pauseProxy); token.cut(rad);

        (,,, line4,) = dss.vat.ilks(token.ilk());
        assertApproxEqAbs(line4, line3 - assets * RAY - line, 0.00000000000000001e45); // Limited by line
    }
}
