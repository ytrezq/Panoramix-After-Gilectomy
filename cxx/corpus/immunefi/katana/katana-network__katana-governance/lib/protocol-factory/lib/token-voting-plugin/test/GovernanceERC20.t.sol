// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

import {TestBase} from "./lib/TestBase.sol";
import {DAO, IDAO} from "@aragon/osx/core/dao/DAO.sol";
import {GovernanceERC20} from "../src/erc20/GovernanceERC20.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC20MintableUpgradeable} from "../src/erc20/IERC20MintableUpgradeable.sol";

contract GovernanceERC20Test is TestBase {
    address internal DAO_BASE = address(new DAO());

    DAO internal dao;
    GovernanceERC20 internal token;

    string constant TOKEN_NAME = "Governance Token";
    string constant TOKEN_SYMBOL = "GOV";

    address internal from;
    address internal to;
    address internal other;
    address internal toDelegate;
    address internal fromDelegate;

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event MintingFrozen();

    error MintingIsFrozen();

    function setUp() public {
        dao = DAO(
            payable(
                ProxyLib.deployUUPSProxy(
                    DAO_BASE,
                    // The test contract is the owner of the DAO
                    abi.encodeWithSelector(DAO.initialize.selector, "Test DAO", address(this), address(0), "")
                )
            )
        );

        address[] memory receivers = new address[](3);
        receivers[0] = alice;
        receivers[1] = bob;
        receivers[2] = carol;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts, ensureDelegationOnMint: true});
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);
    }

    modifier givenTheContractIsBeingDeployedWithDefaultMintSettings() {
        _;
    }

    function test_WhenCallingInitializeAgain() external givenTheContractIsBeingDeployedWithDefaultMintSettings {
        // It reverts if trying to re-initialize
        GovernanceERC20.MintSettings memory emptyMintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: false
        });
        vm.expectRevert("Initializable: contract is already initialized");
        token.initialize(dao, TOKEN_NAME, TOKEN_SYMBOL, emptyMintSettings);
    }

    function test_WhenCheckingTheTokenNameAndSymbol()
        external
        view
        givenTheContractIsBeingDeployedWithDefaultMintSettings
    {
        // It sets the token name and symbol
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
    }

    function test_WhenCheckingTheManagingDAO() external view givenTheContractIsBeingDeployedWithDefaultMintSettings {
        // It sets the managing DAO
        assertEq(address(token.dao()), address(dao));
    }

    function test_WhenDeployingWithMismatchedReceiversAndAmountsArrays() external {
        // It reverts if the `receivers` and `amounts` array lengths in the mint settings mismatch

        address[] memory receivers = new address[](1);
        receivers[0] = alice;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts, ensureDelegationOnMint: false});

        vm.expectRevert(
            abi.encodeWithSelector(
                GovernanceERC20.MintSettingsArrayLengthMismatch.selector, receivers.length, amounts.length
            )
        );
        new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);
    }

    modifier givenTheContractIsBeingDeployedWithSpecificMintSettings() {
        _;
    }

    modifier givenTheEnsureDelegationOnMintFlagIsSetToTrue() {
        address[] memory receivers = new address[](3);
        receivers[0] = alice;
        receivers[1] = bob;
        receivers[2] = carol;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts, ensureDelegationOnMint: true});
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);

        _;
    }

    function test_WhenDeployingWithInitialBalances()
        external
        givenTheContractIsBeingDeployedWithSpecificMintSettings
        givenTheEnsureDelegationOnMintFlagIsSetToTrue
    {
        // It self-delegates for all initial receivers

        vm.roll(block.number + 1);

        assertEq(token.delegates(alice), alice);
        assertEq(token.delegates(bob), bob);
        assertEq(token.delegates(carol), carol);

        assertEq(token.getVotes(alice), 100 ether);
        assertEq(token.getVotes(bob), 200 ether);
        assertEq(token.getVotes(carol), 300 ether);

        assertEq(token.totalSupply(), 600 ether);
        assertEq(token.getPastTotalSupply(block.number - 1), 600 ether);
    }

    modifier givenTheEnsureDelegationOnMintFlagIsSetToFalse() {
        address[] memory receivers = new address[](3);
        receivers[0] = alice;
        receivers[1] = bob;
        receivers[2] = carol;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts, ensureDelegationOnMint: false});
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);

        _;
    }

    function test_WhenDeployingWithInitialBalances2()
        external
        givenTheContractIsBeingDeployedWithSpecificMintSettings
        givenTheEnsureDelegationOnMintFlagIsSetToFalse
    {
        // It does not delegate for any initial receivers

        vm.roll(block.number + 1);

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), address(0));
        assertEq(token.delegates(carol), address(0));

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(carol), 0);

        assertEq(token.totalSupply(), 600 ether);
        assertEq(token.getPastTotalSupply(block.number - 1), 600 ether);
    }

    modifier givenTheContractIsDeployed() {
        GovernanceERC20.MintSettings memory emptyMintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: false
        });
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, emptyMintSettings);
        _;
    }

    function test_WhenCallingSupportsInterfaceWithTheEmptyInterface() external givenTheContractIsDeployed {
        // It does not support the empty interface
        assertFalse(token.supportsInterface(0xffffffff));
    }

    function test_WhenCallingSupportsInterfaceWithTheIERC165UpgradeableInterface()
        external
        givenTheContractIsDeployed
    {
        // It supports the `IERC165Upgradeable` interface
        assertTrue(token.supportsInterface(type(IERC165Upgradeable).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceWithAllInheritedInterfaces() external givenTheContractIsDeployed {
        // It it supports all inherited interfaces
        assertTrue(token.supportsInterface(type(IERC20Upgradeable).interfaceId));
        assertTrue(token.supportsInterface(type(IERC20PermitUpgradeable).interfaceId));
        assertTrue(token.supportsInterface(type(IVotesUpgradeable).interfaceId));
        assertTrue(token.supportsInterface(type(IERC20MintableUpgradeable).interfaceId));
        assertTrue(token.supportsInterface(type(IERC20MetadataUpgradeable).interfaceId));
    }

    modifier givenTheContractIsDeployed2() {
        // Same as givenTheContractIsDeployed, used for logical separation

        GovernanceERC20.MintSettings memory emptyMintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: false
        });
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, emptyMintSettings);
        _;
    }

    modifier givenTheCallerIsMissingTheMINTPERMISSIONID() {
        // By default, Alice does not have the permission
        vm.prank(alice);
        _;
    }

    function test_WhenCallingMint() external givenTheContractIsDeployed2 givenTheCallerIsMissingTheMINTPERMISSIONID {
        // It reverts if the `MINT_PERMISSION_ID` permission is missing
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(token), address(this), token.MINT_PERMISSION_ID()
            )
        );
        token.mint(alice, 100 ether);
    }

    modifier givenTheCallerHasTheMINTPERMISSIONID() {
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());
        _;
    }

    function test_WhenCallingMint2() external givenTheContractIsDeployed2 givenTheCallerHasTheMINTPERMISSIONID {
        // It mints tokens if the caller has the `mintPermission`
        uint256 amount = 100 ether;
        uint256 initialBalance = token.balanceOf(bob);

        token.mint(bob, amount);

        assertEq(token.balanceOf(bob), initialBalance + amount);
    }

    modifier givenTheContractIsDeployedWithInitialBalances() {
        // Same as givenTheContractIsBeingDeployedWithDefaultMintSettings, used for logical separation

        address[] memory receivers = new address[](3);
        receivers[0] = alice;
        receivers[1] = bob;
        receivers[2] = carol;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        amounts[2] = 300 ether;

        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts, ensureDelegationOnMint: true});
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);
        _;
    }

    function test_WhenDelegatingVotingPowerToAnotherAccount() external givenTheContractIsDeployedWithInitialBalances {
        // It delegates voting power to another account
        uint256 aliceBalance = token.balanceOf(alice);
        uint256 bobBalance = token.balanceOf(bob);

        // Initially, users self-delegate upon receiving tokens (because ensureDelegationOnMint is true)
        assertEq(token.delegates(alice), alice);
        assertEq(token.delegates(bob), bob);
        assertEq(token.getVotes(alice), aliceBalance);
        assertEq(token.getVotes(bob), bobBalance);

        vm.prank(alice);
        token.delegate(bob);

        assertEq(token.delegates(alice), bob);
        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), aliceBalance + bobBalance);
    }

    function test_WhenDelegatingVotingPowerMultipleTimes() external givenTheContractIsDeployedWithInitialBalances {
        // It is checkpointed
        uint256 aliceBalance = token.balanceOf(alice);
        uint256 bobBalance = token.balanceOf(bob);
        uint256 carolBalance = token.balanceOf(carol);

        vm.prank(alice);
        token.delegate(bob);
        uint256 block1 = block.number;
        vm.roll(block.number + 1);

        // Check votes at block1
        assertEq(token.getPastVotes(alice, block1), 0);
        assertEq(token.getPastVotes(bob, block1), aliceBalance + bobBalance);
        assertEq(token.getPastVotes(carol, block1), carolBalance);

        vm.prank(alice);
        token.delegate(carol);

        // Check current votes
        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), bobBalance);
        assertEq(token.getVotes(carol), carolBalance + aliceBalance);

        // Check past votes remain correct
        assertEq(token.getPastVotes(alice, block1), 0);
        assertEq(token.getPastVotes(bob, block1), aliceBalance + bobBalance);
        assertEq(token.getPastVotes(carol, block1), carolBalance);
    }

    modifier givenATokenIsDeployedAndTheMainSignerCanMint() {
        // Deploy with ensureDelegationOnMint enabled to test delegation behaviors
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: true
        });
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);

        // Grant mint permission to the test contract
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());
        _;
    }

    modifier givenTheReceiverTurnedDelegationOff() {
        // Bob then manually turns off delegation
        vm.prank(bob);
        token.delegate(address(0));

        _;
    }

    function test_WhenMintingTokensToTheReceiver()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
        givenTheReceiverTurnedDelegationOff
    {
        // It self-delegates the receiver's voting power

        token.mint(alice, 10 ether);
        token.mint(bob, 10 ether);
        token.mint(carol, 10 ether);

        assertEq(token.delegates(alice), alice);
        assertEq(token.delegates(bob), bob);
        assertEq(token.delegates(carol), carol);
        assertEq(token.delegates(david), address(0));

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 10 ether);
        assertEq(token.balanceOf(carol), 10 ether);
        assertEq(token.balanceOf(david), 0);

        assertEq(token.getVotes(alice), 10 ether);
        assertEq(token.getVotes(bob), 10 ether);
        assertEq(token.getVotes(carol), 10 ether);
        assertEq(token.getVotes(david), 0);
    }

    modifier givenTheContractWasDeployedWithEnsureDelegationOnMintAsTrue() {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: true
        });
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);

        // Grant mint permission to the test contract
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());

        _;
    }

    modifier givenTheReceiverHasAlreadyDelegatedToAnotherAccount() {
        vm.prank(bob);
        token.delegate(david);

        _;
    }

    modifier givenTheReceiverHasNeverHadADelegate() {
        _;
    }

    function test_WhenMintingTokensToTheReceiver2()
        external
        givenTheContractWasDeployedWithEnsureDelegationOnMintAsTrue
        givenTheReceiverHasAlreadyDelegatedToAnotherAccount
    {
        // It does not change the existing delegation

        token.mint(alice, 10 ether);
        token.mint(bob, 5 ether);

        assertEq(token.delegates(alice), alice);
        assertEq(token.delegates(bob), david);

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 5 ether);

        assertEq(token.getVotes(alice), 10 ether);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(david), 5 ether);
    }

    modifier givenTheReceiverHasManuallyDelegatedToAddress0() {
        vm.prank(bob);
        token.delegate(david);
        vm.prank(bob);
        token.delegate(address(0));

        _;
    }

    function test_WhenMintingTokensToTheReceiver3()
        external
        givenTheContractWasDeployedWithEnsureDelegationOnMintAsTrue
        givenTheReceiverHasManuallyDelegatedToAddress0
    {
        // It self-delegates the receiver, overwriting the address(0) delegation

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), address(0));

        token.mint(alice, 10 ether);
        token.mint(bob, 5 ether);

        assertEq(token.delegates(alice), alice);
        assertEq(token.delegates(bob), bob);

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 5 ether);

        assertEq(token.getVotes(alice), 10 ether);
        assertEq(token.getVotes(bob), 5 ether);
    }

    modifier givenTheContractWasDeployedWithEnsureDelegationOnMintAsFalse() {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: false
        });
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);

        // Grant mint permission to the test contract
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());

        _;
    }

    modifier givenTheReceiverHasNeverHadADelegate2() {
        _;
    }

    function test_WhenMintingTokensToTheReceiver4()
        external
        givenTheContractWasDeployedWithEnsureDelegationOnMintAsFalse
        givenTheReceiverHasNeverHadADelegate2
    {
        // It does NOT self-delegate the receiver's voting power

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), address(0));

        token.mint(alice, 10 ether);
        token.mint(bob, 5 ether);

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), address(0));

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 5 ether);

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);
    }

    modifier givenTheReceiverHasAlreadyDelegatedToAnotherAccount2() {
        vm.prank(bob);
        token.delegate(david);

        _;
    }

    function test_WhenMintingTokensToTheReceiver5()
        external
        givenTheContractWasDeployedWithEnsureDelegationOnMintAsFalse
        givenTheReceiverHasAlreadyDelegatedToAnotherAccount2
    {
        // It does not change the existing delegation

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), david);

        token.mint(alice, 10 ether);
        token.mint(bob, 5 ether);

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), david);

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 5 ether);

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);
    }

    modifier givenTheContractIsDeployed3() {
        _;
    }

    modifier givenTheEnsureDelegationOnMintFlagIsTrue() {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: true
        });
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);

        // Grant mint permission to the test contract
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());

        _;
    }

    function test_WhenTransferringTokensToANewAddress()
        external
        givenTheContractIsDeployed3
        givenTheEnsureDelegationOnMintFlagIsTrue
    {
        // It does NOT trigger self-delegation

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), address(0));

        token.mint(alice, 10 ether);
        token.mint(bob, 5 ether);

        assertEq(token.delegates(alice), alice);
        assertEq(token.delegates(bob), bob);

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 5 ether);

        assertEq(token.getVotes(alice), 10 ether);
        assertEq(token.getVotes(bob), 5 ether);

        // Transfer
        vm.prank(bob);
        token.transfer(david, 5 ether);

        assertEq(token.delegates(alice), alice);
        assertEq(token.delegates(bob), bob);
        assertEq(token.delegates(david), address(0));

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(david), 5 ether);

        assertEq(token.getVotes(alice), 10 ether);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(david), 0);
    }

    modifier givenTheEnsureDelegationOnMintFlagIsFalse() {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: false
        });
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);

        // Grant mint permission to the test contract
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());

        _;
    }

    function test_WhenTransferringTokensToANewAddress2()
        external
        givenTheContractIsDeployed3
        givenTheEnsureDelegationOnMintFlagIsFalse
    {
        // It does NOT trigger self-delegation

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), address(0));

        token.mint(alice, 10 ether);
        token.mint(bob, 5 ether);

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), address(0));

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 5 ether);

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);

        // Transfer
        vm.prank(bob);
        token.transfer(david, 5 ether);

        assertEq(token.delegates(alice), address(0));
        assertEq(token.delegates(bob), address(0));
        assertEq(token.delegates(david), address(0));

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(david), 5 ether);

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(david), 0);
    }

    function test_WhenMintingTokensToAnAddressForTheFirstTime() external givenATokenIsDeployedAndTheMainSignerCanMint {
        // It turns on delegation after mint
        assertEq(token.delegates(alice), address(0));
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(alice, address(0), alice);
        token.mint(alice, 1 ether);
        assertEq(token.delegates(alice), alice);
        assertEq(token.getVotes(alice), 1 ether);
    }

    function test_WhenTransferringTokensToAnAddressForTheFirstTime()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
    {
        // It does not turn on delegation for the `to` address after a transfer
        token.mint(alice, 100 ether); // This will self-delegate alice
        assertEq(token.delegates(bob), address(0));

        vm.prank(alice);
        token.transfer(bob, 50 ether);

        // Bob is not self-delegated
        assertEq(token.delegates(bob), address(0));
        assertEq(token.getVotes(bob), 0);
    }

    function test_WhenPerformingAChainOfTransfersABC() external givenATokenIsDeployedAndTheMainSignerCanMint {
        // It updates voting power for the sender, but does not self-delegate for receivers
        token.mint(alice, 100 ether); // A, self-delegates. Votes = 100.

        vm.prank(alice);
        token.transfer(bob, 50 ether); // A -> B. Bob does not delegate.

        vm.prank(bob);
        token.transfer(carol, 25 ether); // B -> C. Carol does not delegate.

        assertEq(token.getVotes(alice), 50 ether);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(carol), 0);
    }

    modifier givenTheReceiverHasManuallyTurnedOffDelegation() {
        token.mint(alice, 100 ether);
        // Mint to Bob so he self-delegates (as per modifier setup)
        token.mint(bob, 50 ether);

        // Bob then manually turns off delegation
        vm.prank(bob);
        token.delegate(address(0));

        _;
    }

    function test_WhenTransferringTokensToTheReceiver()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
        givenTheReceiverHasManuallyTurnedOffDelegation
    {
        // It should not turn on delegation on `transfer` if `to` manually turned it off
        vm.prank(alice);
        token.transfer(bob, 10 ether);
        assertEq(token.delegates(bob), address(0));
        assertEq(token.getVotes(bob), 0);
    }

    function test_WhenMintingTokensToTheReceiver6()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
        givenTheReceiverHasManuallyTurnedOffDelegation
    {
        // It should turn on delegation on `mint` if `to` has no delegate, even if they turned it off before
        uint256 previousBalance = token.balanceOf(bob);
        uint256 mintAmount = 10 ether;

        token.mint(bob, mintAmount);

        // `mint` re-delegates if ensureDelegationOnMint is true and delegates is address(0)
        assertEq(token.delegates(bob), bob);
        assertEq(token.getVotes(bob), previousBalance + mintAmount);
    }

    modifier givenAUserHasPredelegatedBeforeReceivingTokens() {
        // Bob (with 0 balance) pre-delegates to Carol
        vm.prank(bob);
        token.delegate(carol);
        _;
    }

    function test_WhenTransferringTokensToTheUser()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
        givenAUserHasPredelegatedBeforeReceivingTokens
    {
        // It should not rewrite delegation setting for `transfer` if user set it on before receiving tokens
        token.mint(alice, 100 ether);
        vm.prank(alice);
        token.transfer(bob, 50 ether);
        assertEq(token.delegates(bob), carol);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(carol), 50 ether);
    }

    function test_WhenMintingTokensToTheUser()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
        givenAUserHasPredelegatedBeforeReceivingTokens
    {
        // It should not rewrite delegation setting for `mint` if user set it on before receiving tokens
        token.mint(bob, 50 ether);
        assertEq(token.delegates(bob), carol);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(carol), 50 ether);
    }

    modifier givenDelegationWasTurnedOnInThePast() {
        token.mint(alice, 100 ether); // Delegation turned on for alice
        _;
    }

    function test_WhenMintingMoreTokens()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
        givenDelegationWasTurnedOnInThePast
    {
        // It should not turn on delegation on `mint` if it was turned on at least once in the past
        token.mint(alice, 50 ether);
        assertEq(token.getVotes(alice), 150 ether);
    }

    function test_WhenTransferringMoreTokens()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
        givenDelegationWasTurnedOnInThePast
    {
        // It should not turn on delegation on `transfer` if it was turned on at least once in the past
        token.mint(bob, 100 ether); // Delegation on for bob
        vm.prank(alice);
        token.transfer(bob, 50 ether);
        assertEq(token.getVotes(bob), 150 ether);
    }

    function test_WhenTransferringTokensFromAnAddressWithDelegationTurnedOn()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
    {
        // It updates voting power after transfer for `from` if delegation turned on
        token.mint(alice, 100 ether);
        assertEq(token.getVotes(alice), 100 ether);
        vm.prank(alice);
        token.transfer(bob, 30 ether);
        assertEq(token.getVotes(alice), 70 ether);
    }

    function test_WhenTransferringTokensToAnAddressWithDelegationTurnedOn()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint
    {
        // It updates voting power after transfer for `to` if delegation turned on
        token.mint(alice, 100 ether);
        token.mint(bob, 0); // Self-delegate bob
        assertEq(token.getVotes(bob), 0);
        vm.prank(alice);
        token.transfer(bob, 30 ether);
        assertEq(token.getVotes(bob), 30 ether);
    }

    // Exhaustive tests setup
    modifier givenATokenIsDeployedAndTheMainSignerCanMint2() {
        from = alice;
        to = bob;
        other = carol;

        // Deploy with ensureDelegationOnMint enabled to test delegation behaviors
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: true
        });
        token = new GovernanceERC20(dao, TOKEN_NAME, TOKEN_SYMBOL, mintSettings);
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());
        _;
    }

    modifier givenTheToAddressHasAZeroBalance() {
        assertEq(token.balanceOf(to), 0);
        toDelegate = address(0);
        _;
    }

    modifier givenTheToAddressHasDelegatedToOther() {
        vm.prank(to);
        token.delegate(other);
        toDelegate = other;
        _;
    }

    function test_WhenTheToAddressReceivesTokensViaMint()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasAZeroBalance
        givenTheToAddressHasDelegatedToOther
    {
        token.mint(to, 100);

        assertEq(token.getVotes(to), 0, "`to` has the correct voting power");
        assertEq(token.delegates(to), toDelegate, "`to`s delegate has not changed");
        assertEq(token.getVotes(toDelegate), 100, "`to`s delegate has the correct voting power");
    }

    function test_WhenTheToAddressReceivesTokensViaTransferFromFrom()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasAZeroBalance
        givenTheToAddressHasDelegatedToOther
    {
        token.mint(from, 100);
        fromDelegate = from;

        vm.prank(from);
        token.transfer(to, 100);

        assertEq(token.getVotes(from), 0, "`from` has the correct voting power");
        assertEq(token.delegates(from), fromDelegate, "`from`s delegate has not changed");
        assertEq(token.getVotes(fromDelegate), 0, "`from`s delegate has the correct voting power");
        assertEq(token.getVotes(to), 0, "`to` has the correct voting power");
        assertEq(token.delegates(to), toDelegate, "`to`s delegate has not changed");
        assertEq(token.getVotes(toDelegate), 100, "`to`s delegate has the correct voting power");
    }

    modifier givenTheToAddressHasNotDelegatedBefore() {
        toDelegate = address(0);
        _;
    }

    function test_WhenTheToAddressReceivesTokensViaMint2()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasAZeroBalance
        givenTheToAddressHasNotDelegatedBefore
    {
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(to, address(0), to);
        token.mint(to, 100);
        toDelegate = to;

        assertEq(token.getVotes(to), 100, "`to` has the correct voting power");
        assertEq(token.delegates(to), toDelegate, "`to`s delegate has not changed");
        assertEq(token.getVotes(toDelegate), 100, "`to`s delegate has the correct voting power");
    }

    function test_WhenTheToAddressReceivesTokensViaTransferFromFrom2()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasAZeroBalance
        givenTheToAddressHasNotDelegatedBefore
    {
        token.mint(from, 100);
        fromDelegate = from;

        vm.prank(from);
        // `transfer` does not self-delegate
        token.transfer(to, 100);
        toDelegate = address(0);

        assertEq(token.getVotes(from), 0, "`from` has the correct voting power");
        assertEq(token.delegates(from), fromDelegate, "`from`s delegate has not changed");
        assertEq(token.getVotes(fromDelegate), 0, "`from`s delegate has the correct voting power");
        assertEq(token.getVotes(to), 0, "`to` has the correct voting power because they did not delegate");
        assertEq(token.delegates(to), toDelegate, "`to`s delegate has not changed");
    }

    modifier givenTheToAddressHasANonzeroBalance() {
        token.mint(to, 100);
        toDelegate = to;
        _;
    }

    modifier givenTheToAddressHasDelegatedToOther2() {
        vm.prank(to);
        token.delegate(other);
        toDelegate = other;
        _;
    }

    modifier whenTheToAddressReceivesTokensViaMint3() {
        token.mint(to, 100);
        _;
    }

    function test_WhenTheToAddressThenTransfersToOther()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasDelegatedToOther2
        whenTheToAddressReceivesTokensViaMint3
    {
        vm.prank(to);
        token.transfer(other, 100);
        assertEq(token.getVotes(to), 0, "`to` has the correct voting power");
        assertEq(token.delegates(to), toDelegate, "`to`s delegate has not changed");
        assertEq(token.getVotes(toDelegate), 100, "`to`s delegate has the correct voting power");
    }

    function test_WhenTheToAddressThenDelegatesToOtherAgain()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasDelegatedToOther2
        whenTheToAddressReceivesTokensViaMint3
    {
        vm.prank(to);
        token.delegate(other);
        assertEq(token.getVotes(to), 0, "`to` has the correct voting power");
        assertEq(token.delegates(to), other, "`to`s delegate is correctly changed");
        assertEq(token.getVotes(other), 200, "`to`s delegate has the correct voting power");
    }

    modifier whenTheToAddressReceivesTokensViaTransferFromFrom3() {
        token.mint(from, 100);
        fromDelegate = from;
        vm.prank(from);
        token.transfer(to, 100);
        _;
    }

    function test_WhenTheToAddressThenTransfersToOther2()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasDelegatedToOther2
        whenTheToAddressReceivesTokensViaTransferFromFrom3
    {
        vm.prank(to);
        token.transfer(other, 100);

        assertEq(token.getVotes(to), 0, "`to` has the correct voting power");
        assertEq(token.delegates(to), toDelegate, "`to`s delegate has not changed");
        assertEq(token.getVotes(toDelegate), 100, "`to`s delegate has the correct voting power");
    }

    function test_WhenTheToAddressThenDelegatesToOtherAgain2()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasDelegatedToOther2
        whenTheToAddressReceivesTokensViaTransferFromFrom3
    {
        vm.prank(to);
        token.delegate(other);
        assertEq(token.getVotes(to), 0, "`to` has the correct voting power");
        assertEq(token.delegates(to), other, "`to`s delegate is correctly changed");
        assertEq(token.getVotes(other), 200, "`to`s delegate has the correct voting power");
    }

    modifier givenTheToAddressHasNotDelegatedBefore2() {
        // This is the default state after the non-zero balance is minted.
        // `to` is self-delegated.
        _;
    }

    modifier whenTheToAddressReceivesTokensViaMint4() {
        token.mint(to, 100);
        _;
    }

    function test_WhenTheToAddressThenTransfersToOther3()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasNotDelegatedBefore2
        whenTheToAddressReceivesTokensViaMint4
    {
        vm.prank(to);
        token.transfer(other, 100);
        assertEq(token.getVotes(to), 100, "`to` has the correct voting power");
        assertEq(token.delegates(to), toDelegate, "`to`s delegate has not changed");
        assertEq(token.getVotes(toDelegate), 100, "`to`s delegate has the correct voting power");
    }

    function test_WhenTheToAddressThenDelegatesToOther()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasNotDelegatedBefore2
        whenTheToAddressReceivesTokensViaMint4
    {
        vm.prank(to);
        token.delegate(other);
        assertEq(token.getVotes(to), 0, "`to` has the correct voting power");
        assertEq(token.delegates(to), other, "`to`s delegate is correctly changed");
        assertEq(token.getVotes(other), 200, "`to`s delegate has the correct voting power");
    }

    modifier whenTheToAddressReceivesTokensViaTransferFromFrom4() {
        token.mint(from, 100);
        fromDelegate = from;
        vm.prank(from);
        token.transfer(to, 100);
        _;
    }

    function test_WhenTheToAddressThenTransfersToOther4()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasNotDelegatedBefore2
        whenTheToAddressReceivesTokensViaTransferFromFrom4
    {
        vm.prank(to);
        token.transfer(other, 100);

        assertEq(token.getVotes(to), 100, "`to` has the correct voting power");
        assertEq(token.delegates(to), toDelegate, "`to`s delegate has not changed");
        assertEq(token.getVotes(toDelegate), 100, "`to`s delegate has the correct voting power");
    }

    function test_WhenTheToAddressThenDelegatesToOther2()
        external
        givenATokenIsDeployedAndTheMainSignerCanMint2
        givenTheToAddressHasANonzeroBalance
        givenTheToAddressHasNotDelegatedBefore2
        whenTheToAddressReceivesTokensViaTransferFromFrom4
    {
        vm.prank(to);
        token.delegate(other);

        assertEq(token.getVotes(to), 0, "`to` has the correct voting power");
        assertEq(token.delegates(to), other, "`to`s delegate is correctly changed");
        assertEq(token.getVotes(other), 200, "`to`s delegate has the correct voting power");
    }

    modifier givenMintingIsAllowed() {
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());

        _;
    }

    function test_GivenCallingMintWithThePermission() external givenMintingIsAllowed {
        // It Should mint properly
        uint256 initialBalance = token.balanceOf(alice);
        uint256 initialSupply = token.totalSupply();

        token.mint(alice, 10 ether);
        assertEq(token.balanceOf(alice), initialBalance + 10 ether);
        assertEq(token.totalSupply(), initialSupply + 10 ether);
    }

    function test_RevertGiven_CallingMintWithoutThePermission() external givenMintingIsAllowed {
        // It Should revert
        uint256 initialBalance = token.balanceOf(alice);
        uint256 initialSupply = token.totalSupply();

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(token), bob, token.MINT_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        token.mint(alice, 10 ether);
        assertEq(token.balanceOf(alice), initialBalance);
        assertEq(token.totalSupply(), initialSupply);
    }

    function test_GivenCallingFreezeMintingWithThePermission() external givenMintingIsAllowed {
        // It Should disallow mints from then on

        uint256 initialBalance = token.balanceOf(alice);
        uint256 initialSupply = token.totalSupply();

        token.mint(alice, 10 ether);
        assertEq(token.balanceOf(alice), initialBalance + 10 ether);
        assertEq(token.totalSupply(), initialSupply + 10 ether);

        vm.expectEmit();
        emit MintingFrozen();
        token.freezeMinting();

        assertTrue(token.getMintingFrozen());

        // KO
        initialBalance = token.balanceOf(alice);
        initialSupply = token.totalSupply();

        vm.expectRevert(MintingIsFrozen.selector);
        token.mint(alice, 10 ether);
        assertEq(token.balanceOf(alice), initialBalance);
        assertEq(token.totalSupply(), initialSupply);
        assertTrue(token.getMintingFrozen());
    }

    function test_RevertGiven_CallingFreezeMintingWithoutThePermission() external givenMintingIsAllowed {
        // It Should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(token), bob, token.MINT_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        token.freezeMinting();

        assertFalse(token.getMintingFrozen());
    }

    modifier givenMintingIsFrozen() {
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());
        token.freezeMinting();

        _;
    }

    function test_RevertGiven_CallingMintWithThePermission2() external givenMintingIsFrozen {
        // It Should revert
        vm.expectRevert(MintingIsFrozen.selector);
        token.mint(alice, 10 ether);
    }

    function test_RevertGiven_CallingMintWithoutThePermission2() external givenMintingIsFrozen {
        // It Should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(token), bob, token.MINT_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        token.mint(alice, 10 ether);
    }

    function test_GivenCallingFreezeMintingWithThePermission2() external givenMintingIsFrozen {
        // It Should do nothing
        assertTrue(token.getMintingFrozen());

        token.freezeMinting();

        assertTrue(token.getMintingFrozen());
    }

    function test_RevertGiven_CallingFreezeMintingWithoutThePermission2() external givenMintingIsFrozen {
        // It Should revert
        assertTrue(token.getMintingFrozen());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(token), bob, token.MINT_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        token.freezeMinting();

        assertTrue(token.getMintingFrozen());
    }

    function test_endToEndMintingWithSelfDelegation() external givenMintingIsAllowed {
        // It Should mint properly
        token = new GovernanceERC20(
            dao,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            GovernanceERC20.MintSettings({
                receivers: new address[](0),
                amounts: new uint256[](0),
                ensureDelegationOnMint: true
            })
        );
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());

        assertTrue(token.getEnsureDelegationOnMint());

        token.mint(alice, 10 ether);
        token.mint(bob, 10 ether);
        token.mint(carol, 10 ether);
        token.mint(david, 10 ether);

        vm.roll(block.number + 1);

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 10 ether);
        assertEq(token.balanceOf(carol), 10 ether);
        assertEq(token.balanceOf(david), 10 ether);

        assertEq(token.getVotes(alice), 10 ether);
        assertEq(token.getVotes(bob), 10 ether);
        assertEq(token.getVotes(carol), 10 ether);
        assertEq(token.getVotes(david), 10 ether);

        assertEq(token.getPastVotes(alice, block.number - 1), 10 ether);
        assertEq(token.getPastVotes(bob, block.number - 1), 10 ether);
        assertEq(token.getPastVotes(carol, block.number - 1), 10 ether);
        assertEq(token.getPastVotes(david, block.number - 1), 10 ether);

        assertEq(token.totalSupply(), 40 ether);
        assertEq(token.getPastTotalSupply(block.number - 1), 40 ether);

        // Transfer tokens
        address someRecipient = makeAddr("some-wallet");

        vm.prank(alice);
        token.transfer(someRecipient, 10 ether);
        vm.prank(bob);
        token.transfer(someRecipient, 10 ether);
        vm.prank(carol);
        token.transfer(someRecipient, 10 ether);
        vm.prank(david);
        token.transfer(someRecipient, 10 ether);

        vm.roll(block.number + 1);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.balanceOf(david), 0);
        assertEq(token.balanceOf(someRecipient), 40 ether);

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(carol), 0);
        assertEq(token.getVotes(david), 0);
        assertEq(token.getVotes(someRecipient), 0);

        assertEq(token.getPastVotes(alice, block.number - 1), 0);
        assertEq(token.getPastVotes(bob, block.number - 1), 0);
        assertEq(token.getPastVotes(carol, block.number - 1), 0);
        assertEq(token.getPastVotes(david, block.number - 1), 0);
        assertEq(token.getPastVotes(someRecipient, block.number - 1), 0);

        assertEq(token.totalSupply(), 40 ether);
        assertEq(token.getPastTotalSupply(block.number - 1), 40 ether);
    }

    function test_endToEndMintingWithoutSelfDelegation() external givenMintingIsAllowed {
        // It Should mint properly
        token = new GovernanceERC20(
            dao,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            GovernanceERC20.MintSettings({
                receivers: new address[](0),
                amounts: new uint256[](0),
                ensureDelegationOnMint: false
            })
        );
        dao.grant(address(token), address(this), token.MINT_PERMISSION_ID());

        assertFalse(token.getEnsureDelegationOnMint());

        token.mint(alice, 10 ether);
        token.mint(bob, 10 ether);
        token.mint(carol, 10 ether);
        token.mint(david, 10 ether);

        vm.roll(block.number + 1);

        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 10 ether);
        assertEq(token.balanceOf(carol), 10 ether);
        assertEq(token.balanceOf(david), 10 ether);

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);
        assertEq(token.getVotes(carol), 0);
        assertEq(token.getVotes(david), 0);

        assertEq(token.getPastVotes(alice, block.number - 1), 0);
        assertEq(token.getPastVotes(bob, block.number - 1), 0);
        assertEq(token.getPastVotes(carol, block.number - 1), 0);
        assertEq(token.getPastVotes(david, block.number - 1), 0);

        assertEq(token.totalSupply(), 40 ether);
        assertEq(token.getPastTotalSupply(block.number - 1), 40 ether);
    }
}
