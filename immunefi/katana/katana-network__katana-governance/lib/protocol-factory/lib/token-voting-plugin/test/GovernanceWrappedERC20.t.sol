// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {TestBase} from "./lib/TestBase.sol";
import {GovernanceWrappedERC20} from "../src/erc20/GovernanceWrappedERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IGovernanceWrappedERC20} from "../src/erc20/IGovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract GovernanceWrappedERC20Test is TestBase {
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    string internal constant UNDERLYING_TOKEN_NAME = "Token";
    string internal constant UNDERLYING_TOKEN_SYMBOL = "TOK";
    string internal constant WRAPPED_TOKEN_NAME = "GovernanceWrappedToken";
    string internal constant WRAPPED_TOKEN_SYMBOL = "gwTOK";

    ERC20Mock internal underlyingToken;
    GovernanceWrappedERC20 internal governanceToken;

    address internal from;
    address internal to;
    address internal other;
    address internal toDelegate;

    function setUp() public virtual {
        underlyingToken = new ERC20Mock(UNDERLYING_TOKEN_NAME, UNDERLYING_TOKEN_SYMBOL);
        governanceToken = new GovernanceWrappedERC20(
            IERC20Upgradeable(address(underlyingToken)), WRAPPED_TOKEN_NAME, WRAPPED_TOKEN_SYMBOL
        );

        // Assign actors for exhaustive tests
        from = alice;
        to = bob;
        other = carol;
    }

    modifier givenTheContractIsAlreadyInitialized() {
        _;
    }

    function test_WhenCallingInitializeAgain() external givenTheContractIsAlreadyInitialized {
        // It reverts if trying to re-initialize
        vm.expectRevert("Initializable: contract is already initialized");
        governanceToken.initialize(IERC20Upgradeable(address(underlyingToken)), "another name", "another symbol");
    }

    function test_WhenCheckingTheContractsNameAndSymbol() external view givenTheContractIsAlreadyInitialized {
        assertEq(governanceToken.name(), WRAPPED_TOKEN_NAME);
        assertEq(governanceToken.symbol(), WRAPPED_TOKEN_SYMBOL);
    }

    function test_WhenCheckingTheContractsDecimalsWithoutModification()
        external
        view
        givenTheContractIsAlreadyInitialized
    {
        // It should return default decimals if not modified
        assertEq(governanceToken.decimals(), 18);
    }

    function test_WhenCheckingTheContractsDecimalsAfterModification() external givenTheContractIsAlreadyInitialized {
        // It should return modified decimals
        underlyingToken.setDecimals(8);
        assertEq(governanceToken.decimals(), 8);
    }

    modifier givenTheContractIsDeployed() {
        _;
    }

    function test_WhenCallingSupportsInterfaceWithTheEmptyInterface() external view givenTheContractIsDeployed {
        // It does not support the empty interface
        assertFalse(governanceToken.supportsInterface(bytes4(0xffffffff)));
    }

    function test_WhenCallingSupportsInterfaceWithTheIERC165UpgradeableInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IERC165Upgradeable` interface
        assertTrue(governanceToken.supportsInterface(type(IERC165Upgradeable).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIGovernanceWrappedERC20Interface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IGovernanceWrappedERC20` interface
        assertTrue(governanceToken.supportsInterface(type(IGovernanceWrappedERC20).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIERC20UpgradeableInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IERC20Upgradeable` interface
        assertTrue(governanceToken.supportsInterface(type(IERC20Upgradeable).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIERC20PermitUpgradeableInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IERC20PermitUpgradeable` interface
        assertTrue(governanceToken.supportsInterface(type(IERC20PermitUpgradeable).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIVotesUpgradeableInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IVotesUpgradeable` interface
        assertTrue(governanceToken.supportsInterface(type(IVotesUpgradeable).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithTheIERC20MetadataUpgradeableInterface()
        external
        view
        givenTheContractIsDeployed
    {
        // It supports the `IERC20MetadataUpgradeable` interface
        assertTrue(governanceToken.supportsInterface(type(IERC20MetadataUpgradeable).interfaceId));
    }

    modifier givenTheContractIsDeployed2() {
        // setUp() deploys the contract
        _;
    }

    modifier givenTheDepositAmountIsNotApproved() {
        uint256 amount = 100 ether;
        underlyingToken.mint(alice, amount);
        // No approval is given
        _;
    }

    function test_WhenCallingDepositFor() external givenTheContractIsDeployed2 givenTheDepositAmountIsNotApproved {
        // It reverts if the amount is not approved
        vm.expectRevert("ERC20: insufficient allowance");
        governanceToken.depositFor(alice, 100 ether);

        vm.expectRevert("ERC20: insufficient allowance");
        governanceToken.depositFor(alice, 20 ether);

        vm.expectRevert("ERC20: insufficient allowance");
        governanceToken.depositFor(alice, 1 ether);
    }

    modifier givenTheDepositAmountIsApproved() {
        uint256 amount = 100 ether;
        underlyingToken.mint(alice, amount);
        vm.prank(alice);
        underlyingToken.approve(address(governanceToken), amount);
        _;
    }

    function test_WhenCallingDepositFor2() external givenTheContractIsDeployed2 givenTheDepositAmountIsApproved {
        // It deposits an amount of tokens
        uint256 amount = 100 ether;
        uint256 aliceUnderlyingBefore = underlyingToken.balanceOf(alice);
        uint256 aliceWrappedBefore = governanceToken.balanceOf(alice);

        vm.prank(alice);
        governanceToken.depositFor(alice, amount);

        assertEq(underlyingToken.balanceOf(alice), aliceUnderlyingBefore - amount);
        assertEq(governanceToken.balanceOf(alice), aliceWrappedBefore + amount);
    }

    modifier givenTheFullBalanceIsApprovedForDeposit() {
        uint256 amount = 123 ether;
        underlyingToken.mint(alice, amount);
        vm.prank(alice);
        underlyingToken.approve(address(governanceToken), amount);
        _;
    }

    function test_WhenCallingDepositForWithTheFullBalance()
        external
        givenTheContractIsDeployed2
        givenTheFullBalanceIsApprovedForDeposit
    {
        // It updates the available votes
        uint256 amount = 123 ether;
        vm.prank(alice);
        governanceToken.depositFor(alice, amount);
        assertEq(governanceToken.getVotes(alice), amount);
    }

    modifier givenTokensHaveBeenDeposited() {
        uint256 amount = 123 ether;
        underlyingToken.mint(alice, amount);
        vm.prank(alice);
        underlyingToken.approve(address(governanceToken), amount);
        vm.prank(alice);
        governanceToken.depositFor(alice, amount);
        _;
    }

    function test_WhenCallingWithdrawTo() external givenTokensHaveBeenDeposited {
        // It withdraws an amount of tokens
        uint256 withdrawAmount = 100 ether;
        uint256 aliceUnderlyingBefore = underlyingToken.balanceOf(alice);
        uint256 aliceWrappedBefore = governanceToken.balanceOf(alice);

        vm.prank(alice);
        governanceToken.withdrawTo(alice, withdrawAmount);

        assertEq(underlyingToken.balanceOf(alice), aliceUnderlyingBefore + withdrawAmount);
        assertEq(governanceToken.balanceOf(alice), aliceWrappedBefore - withdrawAmount);
    }

    function test_WhenCallingWithdrawToForTheFullBalance() external givenTokensHaveBeenDeposited {
        // It updates the available votes
        uint256 fullBalance = governanceToken.balanceOf(alice);
        vm.prank(alice);
        governanceToken.withdrawTo(alice, fullBalance);
        assertEq(governanceToken.balanceOf(alice), 0);
        assertEq(governanceToken.getVotes(alice), 0);
    }

    modifier givenTokensHaveBeenDepositedAndApprovedForAllHolders() {
        underlyingToken.mint(alice, 100 ether);
        underlyingToken.mint(bob, 200 ether);
        underlyingToken.mint(carol, 300 ether);

        vm.startPrank(alice);
        underlyingToken.approve(address(governanceToken), 100 ether);
        governanceToken.depositFor(alice, 100 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        underlyingToken.approve(address(governanceToken), 200 ether);
        governanceToken.depositFor(bob, 200 ether);
        vm.stopPrank();

        vm.startPrank(carol);
        underlyingToken.approve(address(governanceToken), 300 ether);
        governanceToken.depositFor(carol, 300 ether);
        vm.stopPrank();
        _;
    }

    function test_WhenCallingDelegate() external givenTokensHaveBeenDepositedAndApprovedForAllHolders {
        // It delegates voting power to another account
        uint256 aliceVotes = governanceToken.getVotes(alice);
        uint256 bobVotes = governanceToken.getVotes(bob);

        vm.prank(alice);
        governanceToken.delegate(bob);

        assertEq(governanceToken.delegates(alice), bob);
        assertEq(governanceToken.getVotes(alice), 0);
        assertEq(governanceToken.getVotes(bob), aliceVotes + bobVotes);
    }

    function test_WhenCallingDelegateMultipleTimes() external givenTokensHaveBeenDepositedAndApprovedForAllHolders {
        // It is checkpointed
        vm.prank(alice);
        governanceToken.delegate(bob);

        uint256 blockNumBefore = block.number;
        vm.roll(block.number + 1);

        vm.prank(alice);
        governanceToken.delegate(carol);

        // Check past votes
        assertEq(governanceToken.getPastVotes(alice, blockNumBefore), 0);
        assertEq(governanceToken.getPastVotes(bob, blockNumBefore), 100 ether + 200 ether);
        assertEq(governanceToken.getPastVotes(carol, blockNumBefore), 300 ether);

        // Check current votes
        assertEq(governanceToken.getVotes(alice), 0);
        assertEq(governanceToken.getVotes(bob), 200 ether);
        assertEq(governanceToken.getVotes(carol), 100 ether + 300 ether);
    }

    modifier givenAFreshTokenContractIsDeployedAndBalancesAreSet() {
        underlyingToken.mint(alice, 200 ether);
        underlyingToken.mint(bob, 200 ether);
        vm.prank(alice);
        underlyingToken.approve(address(governanceToken), 200 ether);
        vm.prank(bob);
        underlyingToken.approve(address(governanceToken), 200 ether);
        _;
    }

    function test_WhenMintingTokensForAUser() external givenAFreshTokenContractIsDeployedAndBalancesAreSet {
        // It turns on delegation after mint
        assertEq(governanceToken.delegates(alice), address(0));

        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(alice, address(0), alice);
        vm.prank(alice);
        governanceToken.depositFor(alice, 1 ether);

        assertEq(governanceToken.delegates(alice), alice);
        assertEq(governanceToken.getVotes(alice), 1 ether);
    }

    function test_WhenTransferringTokensToAUserForTheFirstTime()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
    {
        // It turns on delegation for the `to` address after transfer
        vm.prank(alice);
        governanceToken.depositFor(alice, 100 ether); // Alice gets auto-delegation

        assertEq(governanceToken.delegates(bob), address(0));

        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(bob, address(0), bob);
        vm.prank(alice);
        governanceToken.transfer(bob, 50 ether);

        assertEq(governanceToken.delegates(bob), bob);
        assertEq(governanceToken.getVotes(bob), 50 ether);
    }

    function test_WhenTransferringTokensThroughAChainOfUsers()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
    {
        // It turns on delegation for all users in the chain of transfer A => B => C
        vm.prank(alice);
        governanceToken.depositFor(alice, 100 ether);

        vm.prank(alice);
        governanceToken.transfer(bob, 40 ether);

        vm.prank(bob);
        governanceToken.transfer(carol, 20 ether);

        assertEq(governanceToken.getVotes(alice), 60 ether);
        assertEq(governanceToken.getVotes(bob), 20 ether);
        assertEq(governanceToken.getVotes(carol), 20 ether);
    }

    modifier givenTheRecipientHasManuallyTurnedDelegationOff() {
        vm.prank(alice);
        governanceToken.depositFor(alice, 100 ether);
        vm.prank(alice);
        governanceToken.transfer(bob, 50 ether);
        vm.prank(bob);
        governanceToken.delegate(address(0)); // Bob turns delegation off (not needed)
        _;
    }

    function test_WhenTransferringTokensToTheRecipient()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
        givenTheRecipientHasManuallyTurnedDelegationOff
    {
        // It should turn on delegation on `transfer` if `to` is not delegating
        vm.prank(alice);
        governanceToken.transfer(bob, 50 ether);

        assertEq(governanceToken.delegates(bob), bob);
        assertEq(governanceToken.getVotes(bob), 100 ether);
    }

    function test_WhenMintingTokensForTheRecipient() external givenAFreshTokenContractIsDeployedAndBalancesAreSet {
        // It should not turn on delegation on `mint` if `to` manually turned it off
        vm.prank(alice);
        governanceToken.depositFor(alice, 100 ether);
        vm.prank(alice);
        governanceToken.delegate(address(0)); // Alice turns it off
        assertEq(governanceToken.delegates(alice), address(0));

        vm.prank(alice);
        governanceToken.depositFor(alice, 50 ether);

        assertEq(governanceToken.delegates(alice), alice);
        assertEq(governanceToken.getVotes(alice), 150 ether);
    }

    modifier givenTheUserHasSetADelegateBeforeReceivingTokens() {
        vm.prank(bob);
        governanceToken.delegate(carol);
        _;
    }

    function test_WhenTransferringTokensToTheUser()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
        givenTheUserHasSetADelegateBeforeReceivingTokens
    {
        // It should not rewrite delegation setting for `transfer` if user set it on before receiving tokens
        vm.prank(alice);
        governanceToken.depositFor(alice, 10 ether);

        vm.prank(alice);
        governanceToken.transfer(bob, 10 ether);

        assertEq(governanceToken.delegates(bob), carol);
    }

    function test_WhenMintingTokensForTheUser()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
        givenTheUserHasSetADelegateBeforeReceivingTokens
    {
        // It should not rewrite delegation setting for `mint` if user set it on before receiving tokens
        vm.prank(bob);
        governanceToken.depositFor(bob, 10 ether);
        assertEq(governanceToken.delegates(bob), carol);
    }

    modifier givenDelegationWasTurnedOnInThePast() {
        vm.prank(alice);
        governanceToken.depositFor(alice, 100 ether);
        _;
    }

    function test_WhenMintingMoreTokens()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
        givenDelegationWasTurnedOnInThePast
    {
        // It should not turn on delegation on `mint` if it was turned on at least once in the past
        vm.prank(alice);
        governanceToken.depositFor(alice, 100 ether);
        assertEq(governanceToken.getVotes(alice), 200 ether);
    }

    function test_WhenTransferringTokens()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
        givenDelegationWasTurnedOnInThePast
    {
        // It should not turn on delegation on `transfer` if it was turned on at least once in the past
        vm.prank(alice);
        governanceToken.transfer(bob, 50 ether); // First transfer to bob

        vm.prank(alice);
        governanceToken.transfer(bob, 30 ether); // Second transfer to bob
        assertEq(governanceToken.getVotes(bob), 80 ether);
    }

    modifier givenDelegationIsTurnedOnForTheSender() {
        vm.prank(alice);
        governanceToken.depositFor(alice, 100 ether);
        _;
    }

    function test_WhenTransferringTokens2()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
        givenDelegationIsTurnedOnForTheSender
    {
        // It updates voting power after transfer for `from` if delegation turned on
        vm.prank(alice);
        governanceToken.transfer(bob, 30 ether);
        assertEq(governanceToken.getVotes(alice), 70 ether);
    }

    modifier givenDelegationIsTurnedOnForTheRecipient() {
        vm.prank(alice);
        governanceToken.depositFor(alice, 100 ether);
        vm.prank(alice);
        governanceToken.transfer(bob, 30 ether);
        _;
    }

    function test_WhenTransferringTokens3()
        external
        givenAFreshTokenContractIsDeployedAndBalancesAreSet
        givenDelegationIsTurnedOnForTheRecipient
    {
        // It updates voting power after transfer for `to` if delegation turned on
        assertEq(governanceToken.getVotes(bob), 30 ether);
    }

    modifier givenAnExhaustiveTestSetupForTokenTransfers() {
        underlyingToken.mint(from, 200 ether);
        vm.prank(from);
        underlyingToken.approve(address(governanceToken), 200 ether);

        underlyingToken.mint(to, 200 ether);
        vm.prank(to);
        underlyingToken.approve(address(governanceToken), 200 ether);

        underlyingToken.mint(other, 200 ether);
        vm.prank(other);
        underlyingToken.approve(address(governanceToken), 200 ether);
        _;
    }

    modifier givenTheToAddressHasAZeroBalance() {
        assertEq(governanceToken.balanceOf(to), 0);
        toDelegate = address(0);
        _;
    }

    modifier givenTheToAddressHasDelegatedToOther() {
        vm.prank(to);
        governanceToken.delegate(other);
        toDelegate = other;
        _;
    }

    function test_WhenToReceivesTokensViaDepositFor()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasAZeroBalance
        givenTheToAddressHasDelegatedToOther
    {
        vm.prank(to);
        governanceToken.depositFor(to, 100 ether);

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to` delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 100 ether, "`to`s delegate has incorrect voting power");
    }

    function test_WhenToReceivesTokensViaTransferFromFrom()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasAZeroBalance
        givenTheToAddressHasDelegatedToOther
    {
        vm.prank(from);
        governanceToken.depositFor(from, 100 ether);

        vm.prank(from);
        governanceToken.transfer(to, 100 ether);

        assertEq(governanceToken.getVotes(from), 0, "`from` has incorrect voting power");
        assertEq(governanceToken.delegates(from), from, "`from`s delegate has changed");
        assertEq(governanceToken.getVotes(governanceToken.delegates(from)), 0, "`from`s delegate has incorrect power");
        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 100 ether, "`to`s delegate has incorrect voting power");
    }

    modifier givenTheToAddressHasNotDelegatedBefore() {
        _;
    }

    function test_WhenToReceivesTokensViaDepositFor2()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasAZeroBalance
        givenTheToAddressHasNotDelegatedBefore
    {
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(to, address(0), to);
        vm.prank(to);
        governanceToken.depositFor(to, 100 ether);
        toDelegate = to;

        assertEq(governanceToken.getVotes(to), 100 ether, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 100 ether, "`to`s delegate has incorrect voting power");
    }

    function test_WhenToReceivesTokensViaTransferFromFrom2()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasAZeroBalance
        givenTheToAddressHasNotDelegatedBefore
    {
        vm.prank(from);
        governanceToken.depositFor(from, 100 ether);

        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(to, address(0), to);
        vm.prank(from);
        governanceToken.transfer(to, 100 ether);
        toDelegate = to;

        assertEq(governanceToken.getVotes(from), 0, "`from` has incorrect voting power");
        assertEq(governanceToken.delegates(from), from, "`from`s delegate has changed");
        assertEq(governanceToken.getVotes(governanceToken.delegates(from)), 0, "`from`s delegate has incorrect power");
        assertEq(governanceToken.getVotes(to), 100 ether, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 100 ether, "`to`s delegate has incorrect voting power");
    }

    modifier givenTheToAddressHasANonzeroBalance() {
        vm.prank(to);
        governanceToken.depositFor(to, 100 ether);
        toDelegate = to;
        assertEq(governanceToken.balanceOf(to), 100 ether);
        assertEq(governanceToken.getVotes(to), 100 ether);
        _;
    }

    modifier givenTheToAddressHasDelegatedToOther2() {
        vm.prank(to);
        governanceToken.delegate(other);
        toDelegate = other;
        _;
    }

    modifier whenToReceivesMoreTokensViaDepositFor() {
        vm.prank(to);
        governanceToken.depositFor(to, 100 ether);
        assertEq(governanceToken.getVotes(to), 0);
        assertEq(governanceToken.delegates(to), toDelegate);
        assertEq(governanceToken.getVotes(toDelegate), 200 ether);
        _;
    }

    function test_WhenToThenTransfersTokensToOther()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasDelegatedToOther2
        whenToReceivesMoreTokensViaDepositFor
    {
        assertEq(governanceToken.balanceOf(to), 200 ether);
        assertEq(governanceToken.balanceOf(toDelegate), 0);

        vm.prank(to);
        governanceToken.transfer(other, 100 ether); // toDelegate

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 200 ether, "`to`s delegate has incorrect voting power");

        vm.prank(to);
        governanceToken.transfer(david, 50 ether);

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 150 ether, "`to`s delegate has incorrect voting power");
    }

    function test_WhenToThenRedelegatesToOther()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasDelegatedToOther2
        whenToReceivesMoreTokensViaDepositFor
    {
        vm.prank(to);
        governanceToken.delegate(other);

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), other, "`to`s delegate is incorrect");
        assertEq(governanceToken.getVotes(toDelegate), 200 ether, "`to`s delegate has incorrect voting power");
    }

    modifier whenToReceivesMoreTokensViaTransferFromFrom() {
        vm.prank(from);
        governanceToken.depositFor(from, 100 ether);
        vm.prank(from);
        governanceToken.transfer(to, 100 ether);

        assertEq(governanceToken.getVotes(from), 0);
        assertEq(governanceToken.delegates(from), from);
        assertEq(governanceToken.getVotes(governanceToken.delegates(from)), 0);
        assertEq(governanceToken.getVotes(to), 0);
        assertEq(governanceToken.delegates(to), other);
        assertEq(governanceToken.getVotes(toDelegate), 200 ether);
        _;
    }

    function test_WhenToThenTransfersTokensToOther2()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasDelegatedToOther2
        whenToReceivesMoreTokensViaTransferFromFrom
    {
        assertEq(governanceToken.balanceOf(to), 200 ether);
        assertEq(governanceToken.balanceOf(toDelegate), 0);

        vm.prank(to);
        governanceToken.transfer(other, 100 ether); // toDelegate

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 200 ether, "`to`s delegate has incorrect voting power");

        vm.prank(to);
        governanceToken.transfer(david, 50 ether);

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 150 ether, "`to`s delegate has incorrect voting power");
    }

    function test_WhenToThenRedelegatesToOther2()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasDelegatedToOther2
        whenToReceivesMoreTokensViaTransferFromFrom
    {
        vm.prank(to);
        governanceToken.delegate(other);

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), other, "`to`s delegate is incorrect");
        assertEq(governanceToken.getVotes(toDelegate), 200 ether, "`to`s delegate has incorrect voting power");
    }

    modifier givenTheToAddressHasNotDelegatedBeforeReceivingAnInitialBalance() {
        // This is the state set by givenTheToAddressHasANonzeroBalance
        _;
    }

    modifier whenToReceivesMoreTokensViaDepositFor2() {
        vm.prank(to);
        governanceToken.depositFor(to, 100 ether);

        assertEq(governanceToken.getVotes(to), 200 ether);
        assertEq(governanceToken.delegates(to), toDelegate);
        assertEq(governanceToken.getVotes(toDelegate), 200 ether);
        _;
    }

    function test_WhenToThenTransfersTokensToOther3()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasNotDelegatedBeforeReceivingAnInitialBalance
        whenToReceivesMoreTokensViaDepositFor2
    {
        vm.prank(to);
        governanceToken.transfer(other, 100 ether);

        assertEq(governanceToken.getVotes(to), 100 ether, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 100 ether, "`to`s delegate has incorrect voting power");
    }

    function test_WhenToThenDelegatesToOther()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasNotDelegatedBeforeReceivingAnInitialBalance
        whenToReceivesMoreTokensViaDepositFor2
    {
        vm.prank(to);
        governanceToken.delegate(other);
        toDelegate = other;

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), other, "`to`s delegate is incorrect");
        assertEq(governanceToken.getVotes(toDelegate), 200 ether, "`to`s delegate has incorrect voting power");
    }

    modifier whenToReceivesMoreTokensViaTransferFromFrom2() {
        vm.prank(from);
        governanceToken.depositFor(from, 100 ether);
        vm.prank(from);
        governanceToken.transfer(to, 100 ether);

        assertEq(governanceToken.getVotes(from), 0);
        assertEq(governanceToken.delegates(from), from);
        assertEq(governanceToken.getVotes(governanceToken.delegates(from)), 0);
        assertEq(governanceToken.getVotes(to), 200 ether);
        assertEq(governanceToken.delegates(to), toDelegate);
        assertEq(governanceToken.getVotes(toDelegate), 200 ether);
        _;
    }

    function test_WhenToThenTransfersTokensToOther4()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasNotDelegatedBeforeReceivingAnInitialBalance
        whenToReceivesMoreTokensViaTransferFromFrom2
    {
        vm.prank(to);
        governanceToken.transfer(other, 100 ether);

        assertEq(governanceToken.getVotes(to), 100 ether, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), toDelegate, "`to`s delegate has changed");
        assertEq(governanceToken.getVotes(toDelegate), 100 ether, "`to`s delegate has incorrect voting power");
    }

    function test_WhenToThenDelegatesToOther2()
        external
        givenAnExhaustiveTestSetupForTokenTransfers
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasNotDelegatedBeforeReceivingAnInitialBalance
        whenToReceivesMoreTokensViaTransferFromFrom2
    {
        vm.prank(to);
        governanceToken.delegate(other);
        toDelegate = other;

        assertEq(governanceToken.getVotes(to), 0, "`to` has incorrect voting power");
        assertEq(governanceToken.delegates(to), other, "`to`s delegate is incorrect");
        assertEq(governanceToken.getVotes(toDelegate), 200 ether, "`to`s delegate has incorrect voting power");
    }

    function test_endToEndFlow() external {
        underlyingToken.mint(alice, 200 ether);
        underlyingToken.mint(bob, 200 ether);
        underlyingToken.mint(carol, 200 ether);
        underlyingToken.mint(david, 200 ether);

        vm.prank(alice);
        underlyingToken.approve(address(governanceToken), 10 ether);
        vm.prank(bob);
        underlyingToken.approve(address(governanceToken), 10 ether);
        vm.prank(carol);
        underlyingToken.approve(address(governanceToken), 10 ether);
        vm.prank(david);
        underlyingToken.approve(address(governanceToken), 10 ether);

        vm.prank(alice);
        governanceToken.depositFor(alice, 10 ether);
        vm.prank(bob);
        governanceToken.depositFor(bob, 10 ether);
        vm.prank(carol);
        governanceToken.depositFor(randomAddress, 10 ether);
        vm.prank(david);
        governanceToken.depositFor(randomAddress, 10 ether);

        vm.roll(block.number + 1);

        assertEq(governanceToken.balanceOf(alice), 10 ether, "Incorrect balance");
        assertEq(governanceToken.balanceOf(bob), 10 ether, "Incorrect balance");
        assertEq(governanceToken.balanceOf(carol), 0, "Incorrect balance");
        assertEq(governanceToken.balanceOf(david), 0, "Incorrect balance");
        assertEq(governanceToken.balanceOf(randomAddress), 20 ether, "Incorrect balance");

        assertEq(governanceToken.getVotes(alice), 10 ether, "Incorrect votes");
        assertEq(governanceToken.getVotes(bob), 10 ether, "Incorrect votes");
        assertEq(governanceToken.getVotes(carol), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(david), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(randomAddress), 20 ether, "Incorrect votes");

        assertEq(governanceToken.getPastVotes(alice, block.number - 1), 10 ether, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(bob, block.number - 1), 10 ether, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(carol, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(david, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(randomAddress, block.number - 1), 20 ether, "Incorrect past votes");

        assertEq(governanceToken.totalSupply(), 40 ether, "Incorrect supply");
        assertEq(governanceToken.getPastTotalSupply(block.number - 1), 40 ether, "Incorrect past supply");

        // Delegate
        vm.prank(alice);
        governanceToken.delegate(david);

        vm.roll(block.number + 1);

        assertEq(governanceToken.balanceOf(alice), 10 ether, "Incorrect balance");
        assertEq(governanceToken.balanceOf(david), 0, "Incorrect balance");

        assertEq(governanceToken.getVotes(alice), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(david), 10 ether, "Incorrect votes");

        assertEq(governanceToken.getPastVotes(alice, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(david, block.number - 1), 10 ether, "Incorrect past votes");

        // Undelegate
        vm.prank(alice);
        governanceToken.delegate(address(0));

        vm.roll(block.number + 1);

        assertEq(governanceToken.balanceOf(alice), 10 ether, "Incorrect balance");
        assertEq(governanceToken.balanceOf(david), 0, "Incorrect balance");

        assertEq(governanceToken.getVotes(alice), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(david), 0, "Incorrect votes");

        assertEq(governanceToken.getPastVotes(alice, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(david, block.number - 1), 0, "Incorrect past votes");

        // Transfer tokens
        address someRecipient = makeAddr("some-wallet");

        vm.prank(alice);
        governanceToken.transfer(someRecipient, 10 ether);
        vm.prank(bob);
        governanceToken.transfer(someRecipient, 10 ether);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(carol);
        governanceToken.transfer(someRecipient, 10 ether);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(david);
        governanceToken.transfer(someRecipient, 10 ether);
        vm.prank(randomAddress);
        governanceToken.transfer(someRecipient, 20 ether);

        vm.roll(block.number + 1);

        assertEq(governanceToken.balanceOf(alice), 0, "Incorrect balance");
        assertEq(governanceToken.balanceOf(bob), 0, "Incorrect balance");
        assertEq(governanceToken.balanceOf(carol), 0, "Incorrect balance");
        assertEq(governanceToken.balanceOf(david), 0, "Incorrect balance");
        assertEq(governanceToken.balanceOf(randomAddress), 0, "Incorrect balance");
        assertEq(governanceToken.balanceOf(someRecipient), 40 ether, "Incorrect balance");

        assertEq(governanceToken.getVotes(alice), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(bob), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(carol), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(david), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(randomAddress), 0, "Incorrect votes");
        assertEq(governanceToken.getVotes(someRecipient), 40 ether, "Incorrect votes");

        assertEq(governanceToken.getPastVotes(alice, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(bob, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(carol, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(david, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(randomAddress, block.number - 1), 0, "Incorrect past votes");
        assertEq(governanceToken.getPastVotes(someRecipient, block.number - 1), 40 ether, "Incorrect past votes");

        assertEq(governanceToken.totalSupply(), 40 ether);
        assertEq(governanceToken.getPastTotalSupply(block.number - 1), 40 ether);
    }
}
