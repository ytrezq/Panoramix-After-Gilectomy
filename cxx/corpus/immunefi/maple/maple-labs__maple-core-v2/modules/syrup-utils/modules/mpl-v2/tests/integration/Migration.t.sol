// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IMigrator } from "../../modules/migrator/contracts/interfaces/IMigrator.sol";

import { NonTransparentProxy } from "../../modules/ntp/contracts/NonTransparentProxy.sol";

import { IMapleToken } from "../../contracts/interfaces/IMapleToken.sol";

import { IGlobalsLike } from "../utils/Interfaces.sol";

import { MapleToken }            from "../../contracts/MapleToken.sol";
import { MapleTokenInitializer } from "../../contracts/MapleTokenInitializer.sol";
import { MapleTokenProxy }       from "../../contracts/MapleTokenProxy.sol";

import { TestBase } from "../utils/TestBase.sol";

contract MigratorIntegrationTest is TestBase {

    uint256 constant OLD_SUPPLY = 10_000_000e18;

    address governor        = makeAddr("governor");
    address migratorAddress = makeAddr("migrator");
    address treasury        = makeAddr("treasury");

    uint256 start;

    IGlobalsLike globals;
    IMapleToken  oldToken;
    IMapleToken  token;
    IMigrator    migrator;

    function setUp() public virtual {
        oldToken = IMapleToken(deployMockERC20());

        globals = IGlobalsLike(address(new NonTransparentProxy(governor, deployGlobals())));

        token = IMapleToken(address(
            new MapleTokenProxy(address(globals), address(new MapleToken()), address(new MapleTokenInitializer()), migratorAddress)
        ));

        migrator = IMigrator(deployMigrator(address(oldToken), address(token)));

        start = block.timestamp;
    }

    function deployMigrator(address oldToken_, address newToken_) internal returns (address migratorAddress_) {
        address deployedAddress = deployCode("Migrator.sol", abi.encode(oldToken_, newToken_));
        migratorAddress_ = migratorAddress;

        // Using etch to always get a deterministic address for the migrator
        vm.etch(migratorAddress_, deployedAddress.code);
    }

    function test_migration_setUp() external {
        assertEq(migrator.oldToken(), address(oldToken));
        assertEq(migrator.newToken(), address(token));

        assertEq(token.balanceOf(address(migrator)), OLD_SUPPLY);
    }

    function test_migration_success() external {
        oldToken.mint(address(this), OLD_SUPPLY); // Simulate the full supply
        oldToken.approve(address(migrator), OLD_SUPPLY - 1);

        vm.expectRevert("M:M:TRANSFER_FROM_FAILED");
        migrator.migrate(OLD_SUPPLY);

        oldToken.approve(address(migrator), OLD_SUPPLY);
        migrator.migrate(OLD_SUPPLY);

        assertEq(token.balanceOf(address(this)),     OLD_SUPPLY);
        assertEq(token.balanceOf(address(migrator)), 0);

        assertEq(oldToken.balanceOf(address(this)),     0);
        assertEq(oldToken.balanceOf(address(migrator)), OLD_SUPPLY);
    }

    function testFuzz_migrate_success(uint256 amount_) external {
        amount_ = bound(amount_, 1, OLD_SUPPLY);

        // Mint amount of old token
        oldToken.mint(address(this), amount_);

        // Approve
        oldToken.approve(address(migrator), amount_);

        assertEq(oldToken.allowance(address(this), address(migrator)), amount_);

        assertEq(oldToken.balanceOf(address(this)),     amount_);
        assertEq(oldToken.balanceOf(address(migrator)), 0);
        assertEq(token.balanceOf(address(this)),        0);
        assertEq(token.balanceOf(address(migrator)),    OLD_SUPPLY);

        migrator.migrate(amount_);

        assertEq(oldToken.allowance(address(this), address(migrator)), 0);

        assertEq(oldToken.balanceOf(address(this)),     0);
        assertEq(oldToken.balanceOf(address(migrator)), amount_);
        assertEq(token.balanceOf(address(this)),        amount_);
        assertEq(token.balanceOf(address(migrator)),    OLD_SUPPLY - amount_);
    }

    function testFuzz_migration_specifiedOwner(uint256 amount_) external {
        amount_ = bound(amount_, 1, OLD_SUPPLY);

        address someAccount = makeAddr("someAccount");

        // Mint amount of old token
        oldToken.mint(address(someAccount), amount_);

        // Approve
        vm.prank(someAccount);
        oldToken.approve(address(migrator), amount_);

        assertEq(oldToken.allowance(address(someAccount), address(migrator)), amount_);

        assertEq(oldToken.balanceOf(address(someAccount)), amount_);
        assertEq(oldToken.balanceOf(address(migrator)),    0);
        assertEq(token.balanceOf(address(someAccount)),    0);
        assertEq(token.balanceOf(address(migrator)),       OLD_SUPPLY);

        migrator.migrate(someAccount, amount_);

        assertEq(oldToken.allowance(address(someAccount), address(migrator)), 0);

        assertEq(oldToken.balanceOf(address(someAccount)), 0);
        assertEq(oldToken.balanceOf(address(migrator)),    amount_);
        assertEq(token.balanceOf(address(someAccount)),    amount_);
        assertEq(token.balanceOf(address(migrator)),       OLD_SUPPLY - amount_);
    }

    function testFuzz_migrate_partialMigration(uint256 amount_, uint256 partialAmount_) external {
        amount_        = bound(amount_,        2, OLD_SUPPLY);
        partialAmount_ = bound(partialAmount_, 1, amount_ - 1);

        // Mint amount of old token
        oldToken.mint(address(this), amount_);

        // Approve partial
        oldToken.approve(address(migrator), partialAmount_);

        assertEq(oldToken.allowance(address(this), address(migrator)), partialAmount_);

        assertEq(oldToken.balanceOf(address(this)),     amount_);
        assertEq(oldToken.balanceOf(address(migrator)), 0);
        assertEq(token.balanceOf(address(this)),        0);
        assertEq(token.balanceOf(address(migrator)),    OLD_SUPPLY);

        migrator.migrate(partialAmount_);

        assertEq(oldToken.allowance(address(this), address(migrator)), 0);

        assertEq(oldToken.balanceOf(address(this)),     amount_ - partialAmount_);
        assertEq(oldToken.balanceOf(address(migrator)), partialAmount_);
        assertEq(token.balanceOf(address(this)),        partialAmount_);
        assertEq(token.balanceOf(address(migrator)),    OLD_SUPPLY - partialAmount_);

        uint256 remaining = amount_ - partialAmount_;

        oldToken.approve(address(migrator), remaining);

        migrator.migrate(remaining);

        assertEq(oldToken.allowance(address(this), address(migrator)), 0);

        assertEq(oldToken.balanceOf(address(this)),     0);
        assertEq(oldToken.balanceOf(address(migrator)), amount_);
        assertEq(token.balanceOf(address(this)),        amount_);
        assertEq(token.balanceOf(address(migrator)),    OLD_SUPPLY - amount_);
    }

}
