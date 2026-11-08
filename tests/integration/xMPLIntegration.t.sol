// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IMigrator } from "../../modules/migrator/contracts/interfaces/IMigrator.sol";

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { IMapleToken }           from "../../contracts/interfaces/IMapleToken.sol";
import { MapleToken }            from "../../contracts/MapleToken.sol";
import { MapleTokenInitializer } from "../../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }       from "../../contracts/MapleTokenProxy.sol";

import { IGlobalsLike, IXmplLike } from "../utils/Interfaces.sol";
import { TestBase }                from "../utils/TestBase.sol";

contract xMPLMigration is TestBase {

    uint256 constant OLD_SUPPLY = 10_000_000e18;

    address constant XMPL      = 0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c;
    address constant OLD_TOKEN = 0x33349B282065b0284d756F0577FB39c158F935e6;

    address governor = makeAddr("governor");
    address treasury = makeAddr("treasury");

    uint256 start;

    IGlobalsLike globals;
    IMapleToken  token;
    IMigrator    migrator;

    IMapleToken oldToken = IMapleToken(OLD_TOKEN);
    IXmplLike   xmpl     = IXmplLike(XMPL);

    address migratorAddress = makeAddr("migrator");

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 17622100);

        globals  = IGlobalsLike(address(new NonTransparentProxy(governor, deployGlobals())));
        token    = IMapleToken(address(new MapleTokenProxy(address(globals), address(new MapleToken()), address(new MapleTokenInitializer()), migratorAddress)));
        migrator = IMigrator(deployMigrator(address(oldToken), address(token)));

        start = block.timestamp;
    }

    function deployMigrator(address oldToken_, address newToken_) internal returns (address migratorAddress_) {
        address deployedAddress = deployCode("Migrator.sol", abi.encode(oldToken_, newToken_));
        migratorAddress_ = migratorAddress;

        // Using etch to always get a deterministic address for the migrator
        vm.etch(migratorAddress_, deployedAddress.code);
    }

    function test_xmpl_migration() external {
        address owner = xmpl.owner();

        // Assert the correct setup
        assertEq(migrator.oldToken(),                address(oldToken));
        assertEq(migrator.newToken(),                address(token));
        assertEq(xmpl.asset(),                       address(oldToken));
        assertEq(token.balanceOf(address(migrator)), OLD_SUPPLY);

        // Schedule migration on xMPL contract
        vm.prank(owner);
        xmpl.scheduleMigration(address(migrator), address(token));

        // Assert the correct scheduled migration
        assertEq(xmpl.scheduledMigrator(),           address(migrator));
        assertEq(xmpl.scheduledNewAsset(),           address(token));
        assertEq(xmpl.scheduledMigrationTimestamp(), start + 864000);

        uint256 xMPLBalance = oldToken.balanceOf(address(xmpl));

        // Perform xMPL migration
        vm.expectRevert("xMPL:PM:TOO_EARLY");
        vm.prank(owner);
        xmpl.performMigration();

        vm.warp(start + 864000 + 1);

        vm.prank(owner);
        xmpl.performMigration();

        assertEq(xmpl.asset(), address(token));

        assertEq(token.balanceOf(address(xmpl)),        xMPLBalance);
        assertEq(token.balanceOf(address(migrator)),    OLD_SUPPLY - xMPLBalance);
        assertEq(oldToken.balanceOf(address(xmpl)),     0);
        assertEq(oldToken.balanceOf(address(migrator)), xMPLBalance);

        // Xmpl was cleaned up
        assertEq(xmpl.scheduledMigrator(),           address(0));
        assertEq(xmpl.scheduledNewAsset(),           address(0));
        assertEq(xmpl.scheduledMigrationTimestamp(), 0);
    }

}
