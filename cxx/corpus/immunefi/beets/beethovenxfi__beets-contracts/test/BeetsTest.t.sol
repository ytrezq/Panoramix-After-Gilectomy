// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Beets} from "src/token/Beets.sol";

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract BeetsTest is Test {
    uint256 INITIAL_SUPPLY = 200_000_000 ether;
    uint256 MAX_MINTABLE_FIRST_YEAR = 20_000_000 ether;
    address TOKEN_MINTER_ADDRESS = 0xa1E849B1d6c2Fd31c63EEf7822e9E0632411ada7;
    address TOKEN_MINTER_TARGET = vm.addr(1);
    Beets beetsToken;

    string SONIC_FORK_URL = "https://rpc.soniclabs.com";
    uint256 INITIAL_FORK_BLOCK_NUMBER = 340476;

    uint256 sonicFork;

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        sonicFork = vm.createSelectFork(SONIC_FORK_URL, INITIAL_FORK_BLOCK_NUMBER);

        beetsToken = new Beets(INITIAL_SUPPLY, TOKEN_MINTER_TARGET, TOKEN_MINTER_ADDRESS);
    }

    function testConstructor() public view {
        assertEq(beetsToken.totalSupply(), INITIAL_SUPPLY);
        assertEq(beetsToken.owner(), TOKEN_MINTER_ADDRESS);
        assertEq(beetsToken.startTimestampCurrentYear(), block.timestamp);
        assertEq(beetsToken.amountMintedCurrentYear(), 0);
        assertEq(beetsToken.maxAmountMintableCurrentYear(), MAX_MINTABLE_FIRST_YEAR);
        assertEq(beetsToken.balanceOf(TOKEN_MINTER_TARGET), INITIAL_SUPPLY);
        assertEq(beetsToken.getEndTimestampCurrentYear(), block.timestamp + 365 days);
    }

    function testConstructorErrorZeroSupply() public {
        vm.expectRevert(abi.encodeWithSelector(Beets.InitialSupplyIsZero.selector));
        new Beets(0, TOKEN_MINTER_TARGET, address(this));
    }

    function testConstructorErrorZeroMintTarget() public {
        vm.expectRevert(abi.encodeWithSelector(Beets.InititalMintTargetIsZero.selector));
        new Beets(INITIAL_SUPPLY, address(0), address(this));
    }

    function testConstructorErrorZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Beets.OwnerIsZero.selector));
        new Beets(INITIAL_SUPPLY, TOKEN_MINTER_TARGET, address(0));
    }

    function testPartialMints() public {
        uint256 amount = 1000 ether;
        uint256 amount2 = 100_000 ether;

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amount);

        assertEq(beetsToken.balanceOf(TOKEN_MINTER_ADDRESS), amount);
        assertEq(beetsToken.amountMintedCurrentYear(), amount);
        assertEq(beetsToken.totalSupply(), INITIAL_SUPPLY + amount);
        assertEq(beetsToken.maxAmountMintableCurrentYear(), MAX_MINTABLE_FIRST_YEAR);

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amount2);

        assertEq(beetsToken.balanceOf(TOKEN_MINTER_ADDRESS), amount + amount2);
        assertEq(beetsToken.amountMintedCurrentYear(), amount + amount2);
        assertEq(beetsToken.totalSupply(), INITIAL_SUPPLY + amount + amount2);
        assertEq(beetsToken.maxAmountMintableCurrentYear(), MAX_MINTABLE_FIRST_YEAR);
    }

    function testMultiYearPartialMints() public {
        uint256 amount = 250_000 ether;
        uint256 amount2 = 750_000 ether;
        uint256 amount3 = 10_000_000 ether;

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amount);

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amount2);

        assertEq(beetsToken.totalSupply(), INITIAL_SUPPLY + amount + amount2);

        vm.warp(block.timestamp + 366 days);

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.incrementYear();

        assertEq(beetsToken.startTimestampCurrentYear(), block.timestamp - 1 days);
        assertEq(beetsToken.maxAmountMintableCurrentYear(), 20_100_000 ether);
        assertEq(beetsToken.amountMintedCurrentYear(), 0);

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amount3);
        assertEq(beetsToken.amountMintedCurrentYear(), amount3);
    }

    function testMintUnAuthorized() public {
        uint256 amount = 1000 ether;

        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amount);
    }

    function testMintCurrentYearEndedError() public {
        uint256 amount = 1000 ether;

        vm.warp(block.timestamp + 366 days);

        vm.prank(TOKEN_MINTER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Beets.CurrentYearEnded.selector));
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amount);
    }

    function testMintAmountTooHighError() public {
        uint256 amount = 20_000_001 ether;

        vm.prank(TOKEN_MINTER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Beets.MintAmountTooHigh.selector, MAX_MINTABLE_FIRST_YEAR));
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amount);
    }

    function testMintInYearTwo() public {
        uint256 maxAmountYearOne = 20_000_000 ether;
        uint256 maxAmountYearTwo = 22_000_000 ether;

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, maxAmountYearOne);

        assertEq(beetsToken.balanceOf(TOKEN_MINTER_ADDRESS), maxAmountYearOne);

        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.incrementYear();

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, maxAmountYearTwo);

        assertEq(beetsToken.balanceOf(TOKEN_MINTER_ADDRESS), maxAmountYearOne + maxAmountYearTwo);
    }

    function testMintInYearTwoNoFirstYearMints() public {
        uint256 maxAmountYearTwo = 20_000_000 ether;

        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.incrementYear();

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, maxAmountYearTwo);

        assertEq(beetsToken.balanceOf(TOKEN_MINTER_ADDRESS), maxAmountYearTwo);
        assertEq(beetsToken.totalSupply(), INITIAL_SUPPLY + maxAmountYearTwo);
        assertEq(beetsToken.maxAmountMintableCurrentYear(), MAX_MINTABLE_FIRST_YEAR);
    }

    function testIncrementYearWithMints() public {
        uint256 amountYearOne = 20_000_000 ether;
        uint256 amountYearTwo = 10_000_000 ether;

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amountYearOne);

        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.incrementYear();

        assertEq(beetsToken.startTimestampCurrentYear(), block.timestamp - 1);
        assertEq(beetsToken.amountMintedCurrentYear(), 0);
        assertEq(beetsToken.maxAmountMintableCurrentYear(), 22_000_000 ether);

        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.mint(TOKEN_MINTER_ADDRESS, amountYearTwo);

        assertEq(beetsToken.startTimestampCurrentYear(), block.timestamp - 1);
        assertEq(beetsToken.amountMintedCurrentYear(), amountYearTwo);
        assertEq(beetsToken.maxAmountMintableCurrentYear(), 22_000_000 ether);
    }

    function testIncrementYearNoMints() public {
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(TOKEN_MINTER_ADDRESS);
        beetsToken.incrementYear();

        assertEq(beetsToken.startTimestampCurrentYear(), block.timestamp - 1);
        assertEq(beetsToken.amountMintedCurrentYear(), 0);
        assertEq(beetsToken.maxAmountMintableCurrentYear(), MAX_MINTABLE_FIRST_YEAR);
    }

    function testIncrementYearNotEndedError() public {
        vm.warp(block.timestamp + 364 days);

        vm.prank(TOKEN_MINTER_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Beets.CurrentYearHasNotEnded.selector));
        beetsToken.incrementYear();
    }

    function testIncrementYearUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        beetsToken.incrementYear();
    }
}
