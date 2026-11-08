// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {SonicBeetsMigrator} from "src/token/SonicBeetsMigrator.sol";
import {Beets} from "src/token/Beets.sol";

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract SonicBeetsMigratorTest is Test {
    uint256 INITIAL_SUPPLY = 200_000_000 ether;
    uint256 INITIAL_TRANSFER = 100_000_000 ether;
    address TREASURY = 0xa1E849B1d6c2Fd31c63EEf7822e9E0632411ada7;
    ERC20 sonicBeets;
    ERC20 fantomBeets;
    SonicBeetsMigrator sonicBeetsMigrator;

    string SONIC_FORK_URL = "https://rpc.soniclabs.com";
    uint256 INITIAL_FORK_BLOCK_NUMBER = 340476;

    uint256 sonicFork;

    function setUp() public {
        sonicFork = vm.createSelectFork(SONIC_FORK_URL, INITIAL_FORK_BLOCK_NUMBER);

        sonicBeets = new Beets(INITIAL_SUPPLY, address(this), address(this));
        fantomBeets = new Beets(INITIAL_SUPPLY, address(this), address(this));

        sonicBeetsMigrator = new SonicBeetsMigrator(fantomBeets, sonicBeets, TREASURY);

        sonicBeets.transfer(address(sonicBeetsMigrator), INITIAL_TRANSFER);
    }

    function testConstructor() public view {
        assertEq(address(sonicBeetsMigrator.OPERABEETS()), address(fantomBeets));
        assertEq(address(sonicBeetsMigrator.SONICBEETS()), address(sonicBeets));
        assertEq(address(sonicBeetsMigrator.TREASURY()), TREASURY);
        assertEq(address(sonicBeetsMigrator.admin()), address(this));
    }

    function testExchangeOperaToSonic() public {
        uint256 amount = 100 ether;
        sonicBeetsMigrator.enableOperaToSonic(true);

        fantomBeets.approve(address(sonicBeetsMigrator), amount);
        sonicBeetsMigrator.exchangeOperaToSonic(amount);
        assertEq(sonicBeets.balanceOf(address(this)), INITIAL_SUPPLY - INITIAL_TRANSFER + amount);
        assertEq(fantomBeets.balanceOf(address(sonicBeetsMigrator)), amount);
    }

    function testExchangeOperaToSonicDisabled() public {
        uint256 amount = 100 ether;

        fantomBeets.approve(address(sonicBeetsMigrator), amount);
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.MigrationDisabled.selector));
        sonicBeetsMigrator.exchangeOperaToSonic(amount);
    }

    function testExchangeOperaToSonicInsufficientUserBalance() public {
        uint256 amount = 200_000_001 ether;
        sonicBeetsMigrator.enableOperaToSonic(true);

        fantomBeets.approve(address(sonicBeetsMigrator), amount);
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.UserBalanceInsufficient.selector));
        sonicBeetsMigrator.exchangeOperaToSonic(amount);
    }

    function testExchangeOperaToSonicInsufficientMigratorBalance() public {
        uint256 amount = 100_000_001 ether;
        sonicBeetsMigrator.enableOperaToSonic(true);

        fantomBeets.approve(address(sonicBeetsMigrator), amount);
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.MigratorBalanceInsufficient.selector));
        sonicBeetsMigrator.exchangeOperaToSonic(amount);
    }

    function testExchangeSonicToOpera() public {
        uint256 amount = 100 ether;
        sonicBeetsMigrator.enableOperaToSonic(true);
        sonicBeetsMigrator.enableSonicToOpera(true);

        fantomBeets.approve(address(sonicBeetsMigrator), amount);
        sonicBeetsMigrator.exchangeOperaToSonic(amount);

        sonicBeets.approve(address(sonicBeetsMigrator), amount);
        sonicBeetsMigrator.exchangeSonicToOpera(amount);
        assertEq(sonicBeets.balanceOf(address(this)), INITIAL_SUPPLY - INITIAL_TRANSFER);
        assertEq(fantomBeets.balanceOf(address(sonicBeetsMigrator)), 0);
    }

    function testExchangeSonicToOperaDisabled() public {
        uint256 amount = 100 ether;

        fantomBeets.approve(address(sonicBeetsMigrator), amount);
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.MigrationDisabled.selector));
        sonicBeetsMigrator.exchangeOperaToSonic(amount);
    }

    function testExchangeSonicToOperaInsufficientUserBalance() public {
        uint256 amountToSonic = 10_000 ether;
        sonicBeetsMigrator.enableOperaToSonic(true);
        sonicBeetsMigrator.enableSonicToOpera(true);

        fantomBeets.approve(address(sonicBeetsMigrator), amountToSonic);
        sonicBeetsMigrator.exchangeOperaToSonic(amountToSonic);

        sonicBeets.transfer(vm.addr(1), sonicBeets.balanceOf(address(this)));

        sonicBeets.approve(address(sonicBeetsMigrator), amountToSonic);
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.UserBalanceInsufficient.selector));
        sonicBeetsMigrator.exchangeSonicToOpera(amountToSonic);
    }

    function testExchangeSonicToOperaInsufficientMigratorBalance() public {
        uint256 amountToSonic = 10_000 ether;
        uint256 amountToOpera = amountToSonic + 1;
        sonicBeetsMigrator.enableOperaToSonic(true);
        sonicBeetsMigrator.enableSonicToOpera(true);

        fantomBeets.approve(address(sonicBeetsMigrator), amountToSonic);
        sonicBeetsMigrator.exchangeOperaToSonic(amountToSonic);

        sonicBeets.approve(address(sonicBeetsMigrator), amountToOpera);
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.MigratorBalanceInsufficient.selector));
        sonicBeetsMigrator.exchangeSonicToOpera(amountToOpera);
    }

    function testSetAdmin() public {
        address newAdmin = vm.addr(1);
        sonicBeetsMigrator.setAdmin(newAdmin);
        assertEq(address(sonicBeetsMigrator.admin()), newAdmin);
    }

    function testSetAdminNotAdmin() public {
        address newAdmin = vm.addr(1);
        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.NotAdmin.selector));
        sonicBeetsMigrator.setAdmin(newAdmin);
    }

    function testEnableOperaToSonic() public {
        sonicBeetsMigrator.enableOperaToSonic(true);
        assert(sonicBeetsMigrator.operaToSonicEnabled());
    }

    function testEnableOperaToSonicNotAdmin() public {
        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.NotAdmin.selector));
        sonicBeetsMigrator.enableOperaToSonic(true);
    }

    function testEnableSonicToOpera() public {
        sonicBeetsMigrator.enableSonicToOpera(true);
        assert(sonicBeetsMigrator.sonicToOperaEnabled());
    }

    function testEnableSonicToOperaNotAdmin() public {
        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.NotAdmin.selector));
        sonicBeetsMigrator.enableSonicToOpera(true);
    }

    function testWithdrawOperaBeets() public {
        uint256 amount = 100 ether;
        sonicBeetsMigrator.enableOperaToSonic(true);

        fantomBeets.approve(address(sonicBeetsMigrator), amount);
        sonicBeetsMigrator.exchangeOperaToSonic(amount);

        sonicBeetsMigrator.withdrawOperaBeets();
        assertEq(fantomBeets.balanceOf(TREASURY), amount);
    }

    function testWithdrawOperaBeetsNotAdmin() public {
        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.NotAdmin.selector));
        sonicBeetsMigrator.withdrawOperaBeets();
    }

    function testWithdrawSonicBeets() public {
        uint256 amount = 100 ether;
        sonicBeetsMigrator.enableOperaToSonic(true);

        fantomBeets.approve(address(sonicBeetsMigrator), amount);
        sonicBeetsMigrator.exchangeOperaToSonic(amount);

        sonicBeetsMigrator.withdrawSonicBeets();
        assertEq(sonicBeets.balanceOf(TREASURY), INITIAL_TRANSFER - amount);
    }

    function testWithdrawSonicBeetsNotAdmin() public {
        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodeWithSelector(SonicBeetsMigrator.NotAdmin.selector));
        sonicBeetsMigrator.withdrawSonicBeets();
    }
}
