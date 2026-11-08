// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {TestBase} from "./lib/TestBase.sol";

import {SimpleBuilder} from "./builders/SimpleBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {TokenVoting} from "../src/TokenVoting.sol";
import {MajorityVotingBase, IProposal} from "../src/base/MajorityVotingBase.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IMajorityVoting} from "../src/base/IMajorityVoting.sol";
import {VotingPowerCondition} from "../src/condition/VotingPowerCondition.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Executor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {IProtocolVersion} from "@aragon/osx-commons-contracts/src/utils/versioning/IProtocolVersion.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {GovernanceERC20} from "../src/erc20/GovernanceERC20.sol";
import {
    ERC165Upgradeable,
    IERC165Upgradeable
} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {ERC20ClockMock, ERC20NoClockMock} from "./mocks/ERC20ClockMock.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TokenVotingTest is TestBase {
    // Convenience aliases
    uint64 constant ONE_HOUR = 3600;
    uint64 constant ONE_DAY = 24 * ONE_HOUR;
    uint32 constant RATIO_BASE = 1_000_000;
    uint256 constant PID_1 = 39687166011226163736142959723276339618578320575274405595170535908768147234362;
    bytes32 public constant SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION");

    DAO dao;
    TokenVoting plugin;
    IVotesUpgradeable token;
    VotingPowerCondition condition;

    SimpleBuilder builder;

    event ExcludedFromSupply(address[] accounts);

    error NoVotingPower();

    modifier givenInTheInitializeContext() {
        // Setup shared across initialize tests
        (dao, plugin, token,) = new SimpleBuilder().build();
        _;
    }

    function test_WhenCallingInitializeOnAnAlreadyInitializedPlugin() external givenInTheInitializeContext {
        // GIVEN an already initialized plugin
        // WHEN calling initialize again
        // THEN it reverts
        vm.expectRevert(PluginUUPSUpgradeable.AlreadyInitialized.selector);
        plugin.initialize(
            dao,
            MajorityVotingBase.VotingSettings({
                votingMode: MajorityVotingBase.VotingMode.Standard,
                supportThreshold: 500_000,
                minParticipation: 100_000,
                minDuration: ONE_HOUR,
                minProposerVotingPower: 0
            }),
            token,
            IPlugin.TargetConfig(address(dao), IPlugin.Operation.Call),
            0,
            "",
            new address[](0)
        );
    }

    function test_WhenCallingInitializeOnAnUninitializedPlugin() external givenInTheInitializeContext {
        // GIVEN an uninitialized plugin proxy
        address base = address(new TokenVoting());
        (dao,,,) = new SimpleBuilder().withNewToken(new address[](0), new uint256[](0)).build();
        token = plugin.getVotingToken();

        address proxy = ProxyLib.deployUUPSProxy(base, "");
        plugin = TokenVoting(proxy);

        // WHEN calling initialize
        MajorityVotingBase.VotingSettings memory settings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.EarlyExecution,
            supportThreshold: 400_000, // 40%
            minParticipation: 200_000, // 20%
            minDuration: ONE_DAY,
            minProposerVotingPower: 1 ether
        });
        uint256 minApprovals = 100_000; // 10%
        bytes memory metadata = "ipfs://1234";

        vm.expectEmit(true, true, true, true, address(plugin));
        emit IMembership.MembershipContractAnnounced(address(token));

        plugin.initialize(
            dao,
            settings,
            token,
            IPlugin.TargetConfig(address(dao), IPlugin.Operation.Call),
            minApprovals,
            metadata,
            new address[](0)
        );

        // THEN it sets the voting settings, token, minimal approval and metadata
        assertEq(uint8(plugin.votingMode()), uint8(settings.votingMode));
        assertEq(plugin.supportThreshold(), settings.supportThreshold);
        assertEq(plugin.minParticipation(), settings.minParticipation);
        assertEq(plugin.minDuration(), settings.minDuration);
        assertEq(plugin.minProposerVotingPower(), settings.minProposerVotingPower);
        assertEq(address(plugin.getVotingToken()), address(token));
        assertEq(plugin.minApproval(), minApprovals);
    }

    modifier givenAnIVotesCompatibleToken() {
        (dao, plugin, token,) = new SimpleBuilder().build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenTheTokenIndexesByBlockNumber()
        external
        givenInTheInitializeContext
        givenAnIVotesCompatibleToken
    {
        // It Should use block numbers for indexing
        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("", new Action[](0), 0, 0, bytes(""));

        (,, MajorityVotingBase.ProposalParameters memory parameters,,,,) = plugin.getProposal(proposalId);
        assertEq(parameters.snapshotTimepoint, block.number - 1);

        // 2

        ERC20ClockMock tok = new ERC20ClockMock(false);

        (dao, plugin, token,) = new SimpleBuilder().withToken(IVotesUpgradeable(address(tok))).build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        vm.roll(500);
        vm.prank(alice);
        proposalId = plugin.createProposal("", new Action[](0), 0, 0, bytes(""));

        (,, parameters,,,,) = plugin.getProposal(proposalId);
        assertEq(parameters.snapshotTimepoint, 499);
    }

    function test_WhenTheTokenIndexesByTimestamp() external givenInTheInitializeContext givenAnIVotesCompatibleToken {
        // It Should use timestamps for indexing

        ERC20ClockMock tok = new ERC20ClockMock(true);

        (dao, plugin, token,) = new SimpleBuilder().withToken(IVotesUpgradeable(address(tok))).build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        vm.warp(500000);
        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("", new Action[](0), 0, 0, bytes(""));

        (,, MajorityVotingBase.ProposalParameters memory parameters,,,,) = plugin.getProposal(proposalId);
        assertEq(parameters.snapshotTimepoint, 499999);
    }

    function test_WhenTheTokenDoesNotReportAnyClockData()
        external
        givenInTheInitializeContext
        givenAnIVotesCompatibleToken
    {
        // It Should assume a block number indexing

        ERC20NoClockMock tok = new ERC20NoClockMock();

        (dao, plugin, token,) = new SimpleBuilder().withToken(IVotesUpgradeable(address(tok))).build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        vm.roll(700);
        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("", new Action[](0), 0, 0, bytes(""));

        (,, MajorityVotingBase.ProposalParameters memory parameters,,,,) = plugin.getProposal(proposalId);
        assertEq(parameters.snapshotTimepoint, 699);
    }

    function test_WhenCallingInitializeWithAListOfExcludedAccounts() external givenInTheInitializeContext {
        // It Should correctly add all provided addresses to the excludedAccounts set
        // It Should emit an event
        // It Should allow an empty list of excluded accounts

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;
        address[] memory excluded = new address[](1);
        excluded[0] = alice;

        uint256 proposalId;

        {
            // Simple flow
            (dao, plugin, token,) = new SimpleBuilder().withNewToken(holders, 10 ether).withExcludedAccount(alice)
                .withEarlyExecution().withMinApprovals(1_000_000)
                // 100% approvals required
                .build();
            dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());
            dao.grant(address(plugin), bob, plugin.EXECUTE_PROPOSAL_PERMISSION_ID());

            vm.prank(alice);
            proposalId = plugin.createProposal("", new Action[](0), 0, 0, bytes(""));

            vm.prank(bob);
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, true);

            (bool open, bool executed,,,,,) = plugin.getProposal(proposalId);
            assertFalse(open);
            assertTrue(executed);
        }

        // Manually initializing a plugin fork (to read minApprovals)
        {
            address base = address(new MyTokenVoting());
            (dao,, token,) = new SimpleBuilder().withNewToken(holders, 10 ether).withExcludedAccount(alice).build();

            address proxy = ProxyLib.deployUUPSProxy(base, "");
            MyTokenVoting myPlugin = MyTokenVoting(proxy);
            MajorityVotingBase.VotingSettings memory settings = MajorityVotingBase.VotingSettings({
                votingMode: MajorityVotingBase.VotingMode.EarlyExecution,
                supportThreshold: 400_000, // 40%
                minParticipation: 200_000, // 20%
                minDuration: ONE_DAY,
                minProposerVotingPower: 0
            });
            uint256 minApprovals = 1_000_000; // 100%

            {
                address[] memory addrs = new address[](1);
                addrs[0] = alice;

                vm.expectEmit();
                emit ExcludedFromSupply(addrs);
                myPlugin.initialize(
                    dao,
                    settings,
                    token,
                    IPlugin.TargetConfig(address(dao), IPlugin.Operation.Call),
                    minApprovals,
                    "",
                    excluded
                );
            }

            dao.grant(address(myPlugin), alice, myPlugin.CREATE_PROPOSAL_PERMISSION_ID());

            vm.prank(alice);
            proposalId = myPlugin.createProposal("", new Action[](0), 0, 0, bytes(""));

            assertEq(myPlugin.getProposalMinApprovals(proposalId), 10 ether);
        }
    }

    function test_WhenCallingInitializeWithDuplicateAddressesInTheExcludedAccountsList()
        external
        givenInTheInitializeContext
    {
        // It Should store each address only once in the excludedAccounts set

        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;
        address[] memory excluded = new address[](5);
        excluded[0] = alice;
        excluded[1] = alice;
        excluded[2] = alice;
        excluded[3] = alice;
        excluded[4] = alice;

        address base = address(new MyTokenVoting());
        (dao,, token,) = new SimpleBuilder().withNewToken(holders, 10 ether).withExcludedAccount(alice).build();

        address proxy = ProxyLib.deployUUPSProxy(base, "");
        MyTokenVoting myPlugin = MyTokenVoting(proxy);
        MajorityVotingBase.VotingSettings memory settings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.EarlyExecution,
            supportThreshold: 400_000, // 40%
            minParticipation: 200_000, // 20%
            minDuration: ONE_DAY,
            minProposerVotingPower: 0
        });
        uint256 minApprovals = 1_000_000; // 100%
        bytes memory metadata = "";

        myPlugin.initialize(
            dao,
            settings,
            token,
            IPlugin.TargetConfig(address(dao), IPlugin.Operation.Call),
            minApprovals,
            metadata,
            excluded
        );

        assertEq(myPlugin.excludedAccountsLength(), 1);
    }

    modifier givenInTheERC165Context() {
        (dao, plugin,,) = new SimpleBuilder().build();
        _;
    }

    function test_WhenCallingSupportsInterface0xffffffff() external givenInTheERC165Context {
        // It does not support the empty interface
        assertFalse(plugin.supportsInterface(0xffffffff));
    }

    function test_WhenCallingSupportsInterfaceForIERC165Upgradeable() external givenInTheERC165Context {
        // It supports the `IERC165Upgradeable` interface
        assertTrue(plugin.supportsInterface(type(IERC165Upgradeable).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceForIPlugin() external givenInTheERC165Context {
        // It supports the `IPlugin` interface
        assertTrue(plugin.supportsInterface(type(IPlugin).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceForIProtocolVersion() external givenInTheERC165Context {
        // It supports the `IProtocolVersion` interface
        assertTrue(plugin.supportsInterface(type(IProtocolVersion).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceForIProposal() external givenInTheERC165Context {
        // It supports the `IProposal` interface
        assertTrue(plugin.supportsInterface(type(IProposal).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceForIMembership() external givenInTheERC165Context {
        // It supports the `IMembership` interface
        assertTrue(plugin.supportsInterface(type(IMembership).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceForIMajorityVoting() external givenInTheERC165Context {
        // It supports the `IMajorityVoting` interface
        assertTrue(plugin.supportsInterface(type(IMajorityVoting).interfaceId));
    }

    function test_WhenCallingSupportsInterfaceForTheOldIMajorityVoting() external givenInTheERC165Context {
        // It supports the `IMajorityVoting` OLD interface
        bytes4 oldInterfaceId =
            type(IMajorityVoting).interfaceId ^ plugin.isMinApprovalReached.selector ^ plugin.minApproval.selector;
        assertTrue(plugin.supportsInterface(oldInterfaceId));
    }

    function test_WhenCallingSupportsInterfaceForMajorityVotingBase() external givenInTheERC165Context {
        // It supports the `MajorityVotingBase` interface
        bytes4 interfaceId = plugin.minDuration.selector ^ plugin.minProposerVotingPower.selector
            ^ plugin.votingMode.selector ^ plugin.totalVotingPower.selector ^ plugin.getProposal.selector
            ^ plugin.updateVotingSettings.selector ^ plugin.updateMinApprovals.selector
            ^ bytes4(keccak256("createProposal(bytes,(address,uint256,bytes)[],uint256,uint64,uint64,uint8,bool)"));
        assertTrue(plugin.supportsInterface(interfaceId));
    }

    function test_WhenCallingSupportsInterfaceForTheOldMajorityVotingBase() external givenInTheERC165Context {
        // It supports the `MajorityVotingBase` OLD interface
        bytes4 interfaceId = plugin.minDuration.selector ^ plugin.minProposerVotingPower.selector
            ^ plugin.votingMode.selector ^ plugin.totalVotingPower.selector ^ plugin.getProposal.selector
            ^ plugin.updateVotingSettings.selector
            ^ bytes4(keccak256("createProposal(bytes,(address,uint256,bytes)[],uint256,uint64,uint64,uint8,bool)"));
        assertTrue(plugin.supportsInterface(interfaceId));
    }

    function test_WhenCallingSupportsInterfaceForTokenVoting() external givenInTheERC165Context {
        // It supports the `TokenVoting` interface
        bytes4 interfaceId = plugin.getVotingToken.selector;
        assertTrue(plugin.supportsInterface(interfaceId));
    }

    modifier givenInTheIsMemberContext() {
        address[] memory holders = new address[](1);
        holders[0] = alice;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 1 ether).build();
        token = plugin.getVotingToken();
        _;
    }

    function test_WhenAnAccountOwnsAtLeastOneToken() external givenInTheIsMemberContext {
        // It returns true if the account currently owns at least one token
        assertTrue(plugin.isMember(alice));
        assertFalse(plugin.isMember(bob));
    }

    function test_WhenAnAccountHasAtLeastOneTokenDelegatedToThem() external givenInTheIsMemberContext {
        // It returns true if the account currently has at least one token delegated to her/him
        vm.prank(alice);
        token.delegate(bob);
        assertTrue(plugin.isMember(bob));
    }

    modifier givenInTheIProposalInterfaceFunctionContextForProposalCreation() {
        address[] memory holders = new address[](1);
        holders[0] = alice;
        (dao, plugin,,) = new SimpleBuilder().withEarlyExecution().withSupportThreshold(0).withMinParticipation(0)
            .withMinProposerVotingPower(0).withNewToken(holders, 1 ether).build();

        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), alice, plugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenCreatingAProposalWithCustomEncodedData()
        external
        givenInTheIProposalInterfaceFunctionContextForProposalCreation
    {
        // It creates proposal with default values if `data` param is encoded with custom values
        // allowFailureMap, voteOption, tryEarlyExecution
        bytes memory data = abi.encode(0, IMajorityVoting.VoteOption.Yes, true);

        bytes memory metadata = "0x1234";
        Action[] memory actions = new Action[](0);

        vm.prank(alice);
        uint256 proposalId = plugin.createProposal(metadata, actions, 0, 0, data);

        (bool open, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertFalse(open, "Proposal should be closed because it was executed");
        assertTrue(executed, "Proposal should be executed");
    }

    function test_WhenCreatingAProposalWithEmptyData()
        external
        givenInTheIProposalInterfaceFunctionContextForProposalCreation
    {
        // It creates proposal with default values if `data` param is passed as empty
        bytes memory metadata = "0x1234";
        Action[] memory actions = new Action[](0);

        vm.prank(alice);
        uint256 proposalId = plugin.createProposal(metadata, actions, 0, 0, "");

        (bool open, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertTrue(open, "Proposal should be open");
        assertFalse(executed, "Proposal should not be executed");
    }

    modifier givenAccountExclusion() {
        _;
    }

    function test_WhenCallingTotalVotingPowerWithNoAccountsInTheExcludedList() external givenAccountExclusion {
        // It Should return the token's past total supply

        address[] memory holders = new address[](4);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = carol;
        holders[3] = david;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 10 ether).build();

        vm.roll(block.number + 1);
        assertEq(plugin.totalVotingPower(block.number - 1), 40 ether);
    }

    modifier whenCallingTotalVotingPowerWithOneAccountInTheExcludedList() {
        _;
    }

    function test_GivenTheExcludedAccountHasVotingPowerAtTheGivenTimepoint()
        external
        givenAccountExclusion
        whenCallingTotalVotingPowerWithOneAccountInTheExcludedList
    {
        // It Should return the token's past total supply minus the past votes of the excluded accounts

        address[] memory holders = new address[](4);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = carol;
        holders[3] = david;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 10 ether).withExcludedAccount(alice).build();

        vm.roll(block.number + 1);
        assertEq(plugin.totalVotingPower(block.number - 1), 30 ether);
    }

    modifier whenCreatingAProposal() {
        _;
    }

    function test_GivenTheTotalVotingPowerAfterExcludingAccountsIsGreaterThan0()
        external
        givenAccountExclusion
        whenCallingTotalVotingPowerWithOneAccountInTheExcludedList
        whenCreatingAProposal
    {
        // It Should create the proposal successfully
        // It Should calculate minVotingPower based on the effective total voting power (after exclusions)
        // It Should calculate minApprovalPower based on the effective total voting power (after exclusions)

        address[] memory holders = new address[](4);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = carol;
        holders[3] = david;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 10 ether).withMinParticipation(100_000)
            .withMinApprovals(200_000).withExcludedAccount(alice).build();

        vm.roll(block.number + 1);
        assertEq(plugin.totalVotingPower(block.number - 1), 30 ether);

        // Create proposal
        dao.grant(address(plugin), address(this), keccak256("CREATE_PROPOSAL_PERMISSION"));
        uint256 proposalId = plugin.createProposal("meta", new Action[](0), 0, 0, "");

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        assertEq(params.minVotingPower, 3 ether);
    }

    function test_GivenTheTotalVotingPowerAfterExcludingAccountsIs0()
        external
        givenAccountExclusion
        whenCallingTotalVotingPowerWithOneAccountInTheExcludedList
        whenCreatingAProposal
    {
        // It Should revert with NoVotingPower()

        address[] memory holders = new address[](1);
        holders[0] = alice;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 10 ether).withExcludedAccount(alice).build();

        vm.roll(block.number + 1);
        assertEq(plugin.totalVotingPower(block.number - 1), 0);

        // Create proposal
        dao.grant(address(plugin), address(this), keccak256("CREATE_PROPOSAL_PERMISSION"));

        vm.expectRevert(NoVotingPower.selector);
        plugin.createProposal("meta", new Action[](0), 0, 0, "");
    }

    function test_WhenCallingTotalVotingPowerWithMultipleAccountsInTheExcludedList() external givenAccountExclusion {
        // It Should correctly subtract the past votes of all excluded accounts from the past total supply

        address[] memory holders = new address[](4);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = carol;
        holders[3] = david;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 10 ether).withExcludedAccount(alice)
            .withExcludedAccount(bob).withExcludedAccount(address(this)).build();

        vm.roll(block.number + 1);
        assertEq(plugin.totalVotingPower(block.number - 1), 20 ether);
    }

    function test_WhenCallingTotalVotingPowerWithAnExcludedAccountThatHasZeroVotingPowerAtTheTimepoint()
        external
        givenAccountExclusion
    {
        // It Should produce the same result as if the account was not excluded

        address[] memory holders = new address[](4);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = carol;
        holders[3] = david;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 10 ether).withExcludedAccount(address(this)).build();

        vm.roll(block.number + 1);
        assertEq(plugin.totalVotingPower(block.number - 1), 40 ether);
    }

    /// @dev Internal helper to create a proposal and return its ID.
    function _createDummyProposal(address _proposer) internal returns (uint256 proposalId) {
        vm.prank(_proposer);
        proposalId = plugin.createProposal(
            "0x", // metadata
            new Action[](0), // actions
            0, // allowFailureMap
            0, // startDate
            0, // endDate
            IMajorityVoting.VoteOption.None,
            false // tryEarlyExecution
        );
    }

    modifier givenInTheProposalCreationContext() {
        _;
    }

    modifier givenMinProposerVotingPower0() {
        address[] memory holders = new address[](1);
        holders[0] = alice;

        (dao, plugin,,) = new SimpleBuilder().withMinProposerVotingPower(0).withNewToken(holders, 10 ether).build();
        token = plugin.getVotingToken();
        dao.grant(address(plugin), carol, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenTheCreatorHadNoVotingPower()
        external
        givenInTheProposalCreationContext
        givenMinProposerVotingPower0
    {
        // It creates a proposal if `_msgSender` had no voting power in the last block
        assertEq(GovernanceERC20(address(token)).balanceOf(carol), 0);
        assertEq(token.getPastVotes(carol, block.number - 1), 0);

        uint256 proposalId = _createDummyProposal(carol);
        assertTrue(proposalId > 0, "Proposal should be created");
    }

    modifier givenMinProposerVotingPower02() {
        _;
    }

    modifier givenMinProposerVotingPowerGreaterThan0() {
        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;

        (dao, plugin,,) =
            new SimpleBuilder().withMinProposerVotingPower(5 ether).withNewToken(holders, 10 ether).build();
        token = plugin.getVotingToken();
        _;
    }

    function test_WhenTheCreatorHadInsufficientVotingPower()
        external
        givenInTheProposalCreationContext
        givenMinProposerVotingPowerGreaterThan0
    {
        // It reverts if `_msgSender` had insufficient voting power in the last block
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), carol, plugin.CREATE_PROPOSAL_PERMISSION_ID()
            )
        );
        _createDummyProposal(carol);

        // 2
        vm.prank(alice);
        GovernanceERC20(address(token)).transfer(carol, 4.9 ether); // Not enough

        vm.roll(block.number + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), carol, plugin.CREATE_PROPOSAL_PERMISSION_ID()
            )
        );
        _createDummyProposal(carol);

        // 3 OK
        _createDummyProposal(alice);
    }

    function test_WhenTheCreatorHadSufficientVotingPower()
        external
        givenInTheProposalCreationContext
        givenMinProposerVotingPowerGreaterThan0
    {
        // It creates a proposal if `_msgSender` had sufficient voting power in the last block
        uint256 proposalId = _createDummyProposal(alice);
        (bool open,,,,,,) = plugin.getProposal(proposalId);
        assertTrue(open);

        // Even if they are transferred away
        vm.prank(alice);
        GovernanceERC20(address(token)).transfer(david, 10 ether);

        assertEq(GovernanceERC20(address(token)).balanceOf(alice), 0);
        assertEq(token.getVotes(alice), 0);
        vm.prank(alice);
        plugin.createProposal("0x11", new Action[](0), 0, 0, 0, IMajorityVoting.VoteOption.None, false);
    }

    function test_WhenTheCreatorHasEnoughDelegatedTokens()
        external
        givenInTheProposalCreationContext
        givenMinProposerVotingPowerGreaterThan0
    {
        // It creates a proposal if `_msgSender` owns no tokens but has enough tokens delegated to her/him in the last block
        vm.prank(alice);
        token.delegate(carol);

        vm.roll(block.number + 1);

        uint256 proposalId = _createDummyProposal(carol);
        (bool open,,,,,,) = plugin.getProposal(proposalId);
        assertTrue(open);
    }

    function test_WhenTheTotalTokenSupplyIs0() external givenInTheProposalCreationContext {
        // It reverts if the total token supply is 0
        address[] memory holders = new address[](1);
        holders[0] = alice;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 0).build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        vm.expectRevert(TokenVoting.NoVotingPower.selector);
        _createDummyProposal(alice);
    }

    function test_WhenTheStartDateIsSmallerThanTheCurrentDate() external givenInTheProposalCreationContext {
        (dao, plugin,,) = new SimpleBuilder().build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        // It reverts if the start date is set smaller than the current date
        uint64 invalidStartDate = uint64(block.timestamp - 1);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MajorityVotingBase.DateOutOfBounds.selector, block.timestamp, invalidStartDate)
        );
        plugin.createProposal("0x", new Action[](0), 0, invalidStartDate, 0, IMajorityVoting.VoteOption.None, false);
    }

    function test_WhenTheStartDateWouldCauseAnOverflowWhenCalculatingTheEndDate()
        external
        givenInTheProposalCreationContext
    {
        (dao, plugin,,) = new SimpleBuilder().build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        // It panics if the start date is after the latest start date
        uint64 invalidStartDate = type(uint64).max;
        vm.prank(alice);
        vm.expectRevert();
        plugin.createProposal("0x", new Action[](0), 0, invalidStartDate, 0, IMajorityVoting.VoteOption.None, false);
    }

    function test_WhenTheEndDateIsBeforeTheMinimumDuration() external givenInTheProposalCreationContext {
        (dao, plugin,,) = new SimpleBuilder().build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        // It reverts if the end date is before the earliest end date so that min duration cannot be met
        uint64 startDate = uint64(block.timestamp + ONE_HOUR);
        uint64 invalidEndDate = startDate + uint64(plugin.minDuration() - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.DateOutOfBounds.selector, startDate + plugin.minDuration(), invalidEndDate
            )
        );
        vm.prank(alice);
        plugin.createProposal(
            "0x", new Action[](0), 0, startDate, invalidEndDate, IMajorityVoting.VoteOption.None, false
        );
    }

    function test_WhenTheStartAndEndDatesAreProvidedAsZero() external givenInTheProposalCreationContext {
        (dao, plugin,,) = new SimpleBuilder().build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        // It sets the startDate to now and endDate to startDate + minDuration, if zeros are provided as an inputs
        uint256 proposalId = _createDummyProposal(alice);
        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);

        assertEq(params.startDate, block.timestamp);
        assertEq(params.endDate, block.timestamp + plugin.minDuration());
    }

    function test_WhenMinParticipationCalculationResultsInARemainder() external givenInTheProposalCreationContext {
        // It ceils the `minVotingPower` value if it has a remainder
        address[] memory holders = new address[](1);
        holders[0] = alice;
        (dao, plugin,,) = new SimpleBuilder().withMinParticipation(300_001).withNewToken(holders, 10).build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        uint256 proposalId = _createDummyProposal(alice);
        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);

        assertEq(params.minVotingPower, 4);
    }

    function test_WhenMinParticipationCalculationDoesNotResultInARemainder()
        external
        givenInTheProposalCreationContext
    {
        // It does not ceil the `minVotingPower` value if it has no remainder
        address[] memory holders = new address[](1);
        holders[0] = alice;
        (dao, plugin,,) = new SimpleBuilder().withMinParticipation(250_000).withNewToken(holders, 1 ether) // 1/4
            .build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        uint256 proposalId = _createDummyProposal(alice);
        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);

        assertEq(params.minVotingPower, 0.25 ether);
    }

    function test_WhenCreatingAProposalWithVoteOptionNone() external givenInTheProposalCreationContext {
        (dao, plugin,,) = new SimpleBuilder().build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        // It should create a proposal successfully, but not vote
        vm.prank(alice);
        uint256 proposalId =
            plugin.createProposal("0x", new Action[](0), 0, 0, 0, IMajorityVoting.VoteOption.None, false);

        (,,, MajorityVotingBase.Tally memory tally,,,) = plugin.getProposal(proposalId);
        assertEq(tally.yes, 0);
        assertEq(tally.no, 0);
        assertEq(tally.abstain, 0);
    }

    function test_WhenCreatingAProposalWithAVoteOptionEgYes() external givenInTheProposalCreationContext {
        address[] memory holders = new address[](1);
        holders[0] = alice;

        (dao, plugin,,) = new SimpleBuilder().withNewToken(holders, 1 ether).build();
        token = plugin.getVotingToken();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        // It should create a vote and cast a vote immediately
        vm.expectEmit(true, true, true, true, address(plugin));
        emit IMajorityVoting.VoteCast(PID_1, alice, IMajorityVoting.VoteOption.Yes, 1 ether);

        vm.prank(alice);
        uint256 proposalId =
            plugin.createProposal("0x", new Action[](0), 0, 0, 0, IMajorityVoting.VoteOption.Yes, false);

        (,,, MajorityVotingBase.Tally memory tally,,,) = plugin.getProposal(proposalId);
        assertEq(tally.yes, 1 ether);
        assertEq(uint256(plugin.getVoteOption(proposalId, alice)), uint256(IMajorityVoting.VoteOption.Yes));
    }

    function test_WhenCreatingAProposalWithAVoteOptionBeforeItsStartDate() external givenInTheProposalCreationContext {
        (dao, plugin,,) = new SimpleBuilder().build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        // It reverts creation when voting before the start date
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, PID_1, alice, IMajorityVoting.VoteOption.Yes
            )
        );
        plugin.createProposal(
            "0x", new Action[](0), 0, uint64(block.timestamp + 100), 0, IMajorityVoting.VoteOption.Yes, false
        );
    }

    modifier givenInTheStandardVotingMode() {
        address[] memory holders = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            holders[i] = vm.addr(100 + i);
        }
        uint256 balance = 10 ether;

        (dao, plugin, token,) = new SimpleBuilder().withSupportThreshold(500_000).withMinParticipation(250_000)
            .withNewToken(holders, balance).build();

        dao.grant(address(plugin), address(this), plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), vm.addr(100), plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), address(this), plugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenInteractingWithANonexistentProposal() external givenInTheStandardVotingMode {
        // It reverts if proposal does not exist
        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.NonexistentProposal.selector, 999));
        plugin.canExecute(999);
    }

    function test_WhenVotingBeforeTheProposalHasStarted() external givenInTheStandardVotingMode {
        // It does not allow voting, when the vote has not started yet
        uint64 futureDate = uint64(block.timestamp + 1 days);
        uint256 proposalId =
            plugin.createProposal("0x", new Action[](0), 0, futureDate, 0, IMajorityVoting.VoteOption.None, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, vm.addr(100), IMajorityVoting.VoteOption.Yes
            )
        );
        vm.prank(vm.addr(100));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
    }

    function test_WhenAUserWith0TokensTriesToVote() external givenInTheStandardVotingMode {
        // It should not be able to vote if user has 0 token
        uint256 proposalId = _createDummyProposal(vm.addr(100));

        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, david, IMajorityVoting.VoteOption.Yes
            )
        );
        vm.prank(david); // David has 0 tokens
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
    }

    function test_WhenMultipleUsersVoteYesNoAndAbstain() external givenInTheStandardVotingMode {
        // It increases the yes, no, and abstain count and emits correct events
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        uint256 bal = 10 ether;

        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, vm.addr(101), IMajorityVoting.VoteOption.Yes, bal);
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, vm.addr(102), IMajorityVoting.VoteOption.No, bal);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, vm.addr(103), IMajorityVoting.VoteOption.Abstain, bal);
        vm.prank(vm.addr(103));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Abstain, false);

        (,,, MajorityVotingBase.Tally memory tally,,,) = plugin.getProposal(proposalId);
        assertEq(tally.yes, bal);
        assertEq(tally.no, bal);
        assertEq(tally.abstain, bal);
    }

    function test_WhenAUserTriesToVoteWithVoteOptionNone() external givenInTheStandardVotingMode {
        // It reverts on voting None
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.prank(vm.addr(101));
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, vm.addr(101), IMajorityVoting.VoteOption.None
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.None, false);
    }

    function test_WhenAUserTriesToReplaceTheirExistingVote() external givenInTheStandardVotingMode {
        // It reverts on vote replacement
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        vm.prank(vm.addr(101));
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, vm.addr(101), IMajorityVoting.VoteOption.No
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);
    }

    function test_WhenAProposalMeetsExecutionCriteriaBeforeTheEndDate() external givenInTheStandardVotingMode {
        // It cannot early execute
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        for (uint256 i = 1; i <= 6; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }
        // Support and Participation are high enough, but it's Standard mode
        assertTrue(plugin.isSupportThresholdReachedEarly(proposalId));
        assertTrue(plugin.isMinParticipationReached(proposalId));
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenAProposalMeetsParticipationAndSupportThresholdsAfterTheEndDate()
        external
        givenInTheStandardVotingMode
    {
        // It can execute normally if participation and support are met
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        // 2 yes (20), 1 no (10) -> 3 voters, 30 total votes -> 30% participation, >50% support
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(103));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);

        assertTrue(plugin.canExecute(proposalId));
        plugin.execute(proposalId);
        (bool open, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertFalse(open);
        assertTrue(executed);
    }

    function test_WhenVotingWithTheTryEarlyExecutionOption() external givenInTheStandardVotingMode {
        // It does not execute early when voting with the `tryEarlyExecution` option
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        for (uint256 i = 1; i < 7; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }

        vm.prank(vm.addr(107));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, true); // try early exec

        (, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertFalse(executed);
    }

    function test_WhenTryingToExecuteAProposalThatIsNotYetDecided() external givenInTheStandardVotingMode {
        // It reverts if vote is not decided yet
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.ProposalExecutionForbidden.selector, proposalId));
        plugin.execute(proposalId);
    }

    function test_WhenTheCallerDoesNotHaveEXECUTEPROPOSALPERMISSIONID() external givenInTheStandardVotingMode {
        // It can not execute even if participation and support are met when caller does not have permission
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(103));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);

        dao.revoke(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), bob, plugin.EXECUTE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(bob); // Bob has no permission
        plugin.execute(proposalId);
    }

    modifier givenInTheEarlyExecutionVotingMode() {
        address[] memory holders = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            holders[i] = vm.addr(100 + i);
        }
        uint256 balance = 10 ether;

        (dao, plugin,,) = new SimpleBuilder().withEarlyExecution().withSupportThreshold(500_000).withMinParticipation(
            200_000
        ).withNewToken(holders, balance).build();
        token = plugin.getVotingToken();

        dao.grant(address(plugin), address(this), plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), vm.addr(100), plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), address(this), plugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenInteractingWithANonexistentProposal2() external givenInTheEarlyExecutionVotingMode {
        // It reverts if proposal does not exist
        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.NonexistentProposal.selector, 999));
        plugin.hasSucceeded(999);
    }

    function test_WhenVotingBeforeTheProposalHasStarted2() external givenInTheEarlyExecutionVotingMode {
        // It does not allow voting, when the vote has not started yet
        uint64 futureDate = uint64(block.timestamp + 1 days);
        uint256 proposalId =
            plugin.createProposal("0x", new Action[](0), 0, futureDate, 0, IMajorityVoting.VoteOption.None, false);

        vm.prank(vm.addr(100));
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, vm.addr(100), IMajorityVoting.VoteOption.Yes
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
    }

    function test_WhenAUserWith0TokensTriesToVote2() external givenInTheEarlyExecutionVotingMode {
        // It should not be able to vote if user has 0 token
        uint256 proposalId = _createDummyProposal(vm.addr(100));

        vm.prank(david); // David has 0 tokens
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, david, IMajorityVoting.VoteOption.Yes
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
    }

    function test_WhenMultipleUsersVoteYesNoAndAbstain2() external givenInTheEarlyExecutionVotingMode {
        // It increases the yes, no, and abstain count and emits correct events
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        uint256 bal = 10 ether;

        vm.prank(vm.addr(101));
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, vm.addr(101), IMajorityVoting.VoteOption.Yes, bal);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        vm.prank(vm.addr(102));
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, vm.addr(102), IMajorityVoting.VoteOption.No, bal);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        vm.prank(vm.addr(103));
        vm.expectEmit(true, true, true, true);
        emit IMajorityVoting.VoteCast(proposalId, vm.addr(103), IMajorityVoting.VoteOption.Abstain, bal);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Abstain, false);

        (,,, MajorityVotingBase.Tally memory tally,,,) = plugin.getProposal(proposalId);
        assertEq(tally.yes, bal);
        assertEq(tally.no, bal);
        assertEq(tally.abstain, bal);
    }

    function test_WhenAUserTriesToVoteWithVoteOptionNone2() external givenInTheEarlyExecutionVotingMode {
        // It reverts on voting None
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.prank(vm.addr(101));
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, vm.addr(101), IMajorityVoting.VoteOption.None
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.None, false);
    }

    function test_WhenAUserTriesToReplaceTheirExistingVote2() external givenInTheEarlyExecutionVotingMode {
        // It reverts on vote replacement
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        vm.prank(vm.addr(101));
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, vm.addr(101), IMajorityVoting.VoteOption.No
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);
    }

    function test_WhenParticipationIsLargeEnoughToMakeTheOutcomeUnchangeable()
        external
        givenInTheEarlyExecutionVotingMode
    {
        // It can execute early if participation is large enough
        uint256 proposalId = _createDummyProposal(vm.addr(100));

        // 6/10 vote yes. totalVotingPower = 100. yes = 60.
        // worst case no = 40. 60 > 40. Support threshold reached early.
        // Participation is 60%, > 20%.
        for (uint256 i = 1; i <= 6; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }

        assertTrue(plugin.canExecute(proposalId));
        plugin.execute(proposalId);
        (, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertTrue(executed);
    }

    function test_WhenParticipationAndSupportAreMetAfterTheVotingPeriodEnds()
        external
        givenInTheEarlyExecutionVotingMode
    {
        // It can execute normally if participation is large enough
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        // 2 yes, 1 no -> participation met (30%), support met (66%)
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(103));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        assertFalse(plugin.canExecute(proposalId));

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);

        assertTrue(plugin.canExecute(proposalId));
    }

    function test_WhenParticipationIsTooLowEvenIfSupportIsMet() external givenInTheEarlyExecutionVotingMode {
        // It cannot execute normally if participation is too low
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        // 1 yes -> support 100%, but participation 10% < 20%
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        assertFalse(plugin.canExecute(proposalId));
        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenTheTargetOperationIsADelegatecall() external givenInTheEarlyExecutionVotingMode {
        // It executes target with delegate call
        Executor target = new Executor();
        dao.grant(address(plugin), address(this), SET_TARGET_CONFIG_PERMISSION_ID);
        plugin.setTargetConfig(
            IPlugin.TargetConfig({target: address(target), operation: IPlugin.Operation.DelegateCall})
        );

        uint256 proposalId = _createDummyProposal(vm.addr(100));
        for (uint256 i = 1; i <= 6; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }

        assertTrue(plugin.canExecute(proposalId));
        vm.expectEmit(true, false, false, true);
        emit IProposal.ProposalExecuted(proposalId);
        plugin.execute(proposalId);
    }

    function test_WhenTheVoteIsDecidedEarlyAndTheTryEarlyExecutionOptionIsUsed()
        external
        givenInTheEarlyExecutionVotingMode
    {
        // It executes the vote immediately when the vote is decided early and the tryEarlyExecution options is selected
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }
        assertFalse(plugin.canExecute(proposalId));

        dao.grant(address(plugin), vm.addr(106), plugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        vm.expectEmit(true, true, true, true);
        emit IProposal.ProposalExecuted(proposalId);
        vm.prank(vm.addr(106));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, true);

        (, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertTrue(executed);
    }

    function test_WhenTryingToExecuteAProposalThatIsNotYetDecided2() external givenInTheEarlyExecutionVotingMode {
        // It reverts if vote is not decided yet
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.ProposalExecutionForbidden.selector, proposalId));
        plugin.execute(proposalId);
    }

    function test_WhenTheCallerHasNoExecutionPermissionButTryEarlyExecutionIsSelected()
        external
        givenInTheEarlyExecutionVotingMode
    {
        // It record vote correctly without executing even when tryEarlyExecution options is selected
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }

        vm.prank(vm.addr(106));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, true);

        (,,, MajorityVotingBase.Tally memory tally,,,) = plugin.getProposal(proposalId);
        assertEq(tally.yes, 60 ether);

        (, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertFalse(executed, "Should not execute without permission");
    }

    modifier givenInTheVoteReplacementVotingMode() {
        address[] memory holders = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            holders[i] = vm.addr(100 + i);
        }
        uint256 balance = 10 ether;

        (dao, plugin,,) = new SimpleBuilder().withVoteReplacement().withSupportThreshold(500_000).withMinParticipation(
            200_000
        ).withNewToken(holders, balance).build();
        token = plugin.getVotingToken();

        dao.grant(address(plugin), address(this), plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), vm.addr(100), plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), address(this), plugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenInteractingWithANonexistentProposal3() external givenInTheVoteReplacementVotingMode {
        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.NonexistentProposal.selector, 999));
        plugin.canVote(999, alice, IMajorityVoting.VoteOption.Yes);
    }

    function test_WhenVotingBeforeTheProposalHasStarted3() external givenInTheVoteReplacementVotingMode {
        uint64 futureDate = uint64(block.timestamp + 1 days);
        uint256 proposalId =
            plugin.createProposal("0x", new Action[](0), 0, futureDate, 0, IMajorityVoting.VoteOption.None, false);

        vm.prank(vm.addr(100));
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, vm.addr(100), IMajorityVoting.VoteOption.Yes
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
    }

    function test_WhenAUserWith0TokensTriesToVote3() external givenInTheVoteReplacementVotingMode {
        uint256 proposalId = _createDummyProposal(vm.addr(100));

        vm.prank(david); // David has 0 tokens
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, david, IMajorityVoting.VoteOption.Yes
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
    }

    function test_WhenMultipleUsersVoteYesNoAndAbstain3() external givenInTheVoteReplacementVotingMode {
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        uint256 bal = 10 ether;

        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);
        vm.prank(vm.addr(103));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Abstain, false);

        (,,, MajorityVotingBase.Tally memory tally,,,) = plugin.getProposal(proposalId);
        assertEq(tally.yes, bal);
        assertEq(tally.no, bal);
        assertEq(tally.abstain, bal);
    }

    function test_WhenAUserTriesToVoteWithVoteOptionNone3() external givenInTheVoteReplacementVotingMode {
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.prank(vm.addr(101));
        vm.expectRevert(
            abi.encodeWithSelector(
                MajorityVotingBase.VoteCastForbidden.selector, proposalId, vm.addr(101), IMajorityVoting.VoteOption.None
            )
        );
        plugin.vote(proposalId, IMajorityVoting.VoteOption.None, false);
    }

    function test_WhenAVoterChangesTheirVoteMultipleTimes() external givenInTheVoteReplacementVotingMode {
        // It should allow vote replacement but not double-count votes by the same address
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        uint256 bal = 10 ether;

        vm.startPrank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        (,,, MajorityVotingBase.Tally memory tally1,,,) = plugin.getProposal(proposalId);
        assertEq(tally1.yes, bal);
        assertEq(tally1.no, 0);
        assertEq(tally1.abstain, 0);

        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);
        (,,, MajorityVotingBase.Tally memory tally2,,,) = plugin.getProposal(proposalId);
        assertEq(tally2.yes, 0);
        assertEq(tally2.no, bal);
        assertEq(tally2.abstain, 0);

        plugin.vote(proposalId, IMajorityVoting.VoteOption.Abstain, false);
        (,,, MajorityVotingBase.Tally memory tally3,,,) = plugin.getProposal(proposalId);
        assertEq(tally3.yes, 0);
        assertEq(tally3.no, 0);
        assertEq(tally3.abstain, bal);
        vm.stopPrank();
    }

    function test_WhenAProposalMeetsExecutionCriteriaBeforeTheEndDate2() external givenInTheVoteReplacementVotingMode {
        // It cannot early execute
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        for (uint256 i = 1; i <= 6; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenAProposalMeetsParticipationAndSupportThresholdsAfterTheEndDate2()
        external
        givenInTheVoteReplacementVotingMode
    {
        // It can execute normally if participation and support are met
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(103));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        assertFalse(plugin.canExecute(proposalId));

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);

        assertTrue(plugin.canExecute(proposalId));
    }

    function test_WhenVotingWithTheTryEarlyExecutionOption2() external givenInTheVoteReplacementVotingMode {
        // It does not execute early when voting with the `tryEarlyExecution` option
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        for (uint256 i = 1; i <= 6; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, true);
        }

        (, bool executed,,,,,) = plugin.getProposal(proposalId);
        assertFalse(executed);
    }

    function test_WhenTryingToExecuteAProposalThatIsNotYetDecided3() external givenInTheVoteReplacementVotingMode {
        // It reverts if vote is not decided yet
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        vm.expectRevert(abi.encodeWithSelector(MajorityVotingBase.ProposalExecutionForbidden.selector, proposalId));
        plugin.execute(proposalId);
    }

    modifier givenASimpleMajorityVoteWith50Support25ParticipationRequiredAndMinimalApproval21() {
        address[] memory holders = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            holders[i] = vm.addr(100 + i);
        }
        uint256 balance = 10 ether;

        (dao, plugin,,) = new SimpleBuilder().withEarlyExecution().withSupportThreshold(500_000).withMinParticipation(
            250_000
        ).withMinApprovals(210_000).withNewToken(holders, balance).build();

        dao.grant(address(plugin), address(this), plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), vm.addr(100), plugin.CREATE_PROPOSAL_PERMISSION_ID());
        dao.grant(address(plugin), address(this), plugin.EXECUTE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenSupportIsHighButParticipationIsTooLow()
        external
        givenASimpleMajorityVoteWith50Support25ParticipationRequiredAndMinimalApproval21
    {
        // It does not execute if support is high enough but participation is too low
        uint256 proposalId = _createDummyProposal(vm.addr(100));

        // Yes: 20 (2 voters), No: 0. Total: 20. Participation: 20% < 25%.
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenSupportAndParticipationAreHighButMinimalApprovalIsTooLow()
        external
        givenASimpleMajorityVoteWith50Support25ParticipationRequiredAndMinimalApproval21
    {
        // It does not execute if support and participation are high enough but minimal approval is too low
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        // Yes: 20 (2 voters), No: 10 (1 voter). Total: 30. Participation: 30% >= 25%.
        // Support: 66% > 50%. Min Approval: 20% < 21%.
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(103));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenParticipationIsHighButSupportIsTooLow()
        external
        givenASimpleMajorityVoteWith50Support25ParticipationRequiredAndMinimalApproval21
    {
        // It does not execute if participation is high enough but support is too low
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        // Yes: 10 (1 voter), No: 20 (2 voters). Total: 30. Participation: 30% >= 25%.
        // Support: 33% < 50%.
        vm.prank(vm.addr(101));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(vm.addr(102));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);
        vm.prank(vm.addr(103));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenParticipationAndMinimalApprovalAreHighButSupportIsTooLow()
        external
        givenASimpleMajorityVoteWith50Support25ParticipationRequiredAndMinimalApproval21
    {
        // It does not execute if participation and minimal approval are high enough but support is too low
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        // Yes: 30 (3 voters), No: 40 (4 voters). Total: 70. Participation: 70% >= 25%.
        // Min Approval: 30% >= 21%. Support: 42% < 50%.
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }
        for (uint256 i = 4; i <= 7; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);
        }
        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenAllThresholdsParticipationSupportMinimalApprovalAreMetAfterTheDuration()
        external
        givenASimpleMajorityVoteWith50Support25ParticipationRequiredAndMinimalApproval21
    {
        // It executes after the duration if participation, support and minimal approval are met
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        // Yes: 30 (3 voters), No: 10 (1 voter). Total: 40. Part: 40%>=25%, Supp: 75%>50%, MinApp: 30%>=21%.
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }
        vm.prank(vm.addr(104));
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);
        assertFalse(plugin.canExecute(proposalId));

        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);
        assertTrue(plugin.canExecute(proposalId));
    }

    function test_WhenAllThresholdsAreMetAndTheOutcomeCannotChange()
        external
        givenASimpleMajorityVoteWith50Support25ParticipationRequiredAndMinimalApproval21
    {
        // It executes early if participation, support and minimal approval are met and the vote outcome cannot change anymore
        uint256 proposalId = _createDummyProposal(vm.addr(100));
        // Yes: 70 (7 voters), No: 0. Total: 70.
        // Part: 70%, Supp: 100%, MinApp: 70%. All met.
        // Early Exec: yes / (total - abstain) = 70 / (100 - 0) = 70%.
        // (1-0.5)*70 > 0.5 * (100 - 70) => 35 > 15. True.
        for (uint256 i = 1; i <= 7; i++) {
            vm.prank(vm.addr(100 + i));
            plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        }
        assertTrue(plugin.canExecute(proposalId));
    }

    modifier givenAnEdgeCaseWithSupportThreshold0MinParticipation0MinApproval0InEarlyExecutionMode() {
        (dao, plugin,,) = new SimpleBuilder().withEarlyExecution().withSupportThreshold(0).withMinParticipation(0)
            .withMinApprovals(0).build();

        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenThereAre0Votes()
        external
        givenAnEdgeCaseWithSupportThreshold0MinParticipation0MinApproval0InEarlyExecutionMode
    {
        // It does not execute with 0 votes
        uint256 proposalId = _createDummyProposal(alice);
        assertFalse(plugin.canExecute(proposalId));
        (,, MajorityVotingBase.ProposalParameters memory params,,,,) = plugin.getProposal(proposalId);
        vm.warp(params.endDate);
        assertFalse(plugin.canExecute(proposalId));
    }

    function test_WhenThereIsAtLeastOneYesVote()
        external
        givenAnEdgeCaseWithSupportThreshold0MinParticipation0MinApproval0InEarlyExecutionMode
    {
        // It executes if participation, support and min approval are met
        uint256 proposalId = _createDummyProposal(alice);
        assertFalse(plugin.canExecute(proposalId));

        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        assertTrue(plugin.canExecute(proposalId));
    }

    modifier givenAnEdgeCaseWithSupportThreshold999999MinParticipation100AndMinApproval100InEarlyExecutionMode() {
        builder = new SimpleBuilder().withEarlyExecution().withSupportThreshold(RATIO_BASE - 1).withMinParticipation(
            RATIO_BASE
        ).withMinApprovals(RATIO_BASE);

        _;
    }

    modifier givenTokenBalancesAreInTheMagnitudeOf1018() {
        uint256 totalSupply = 10 ** 18;
        uint256 delta = totalSupply / RATIO_BASE; // 10**12
        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = carol;
        uint256[] memory balances = new uint256[](3);
        balances[0] = totalSupply - delta;
        balances[1] = 1;
        balances[2] = delta - 1;

        (dao, plugin,,) = builder.withNewToken(holders, balances).build();

        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenTheNumberOfYesVotesIsOneShyOfEnsuringTheSupportThresholdCannotBeDefeated()
        external
        givenAnEdgeCaseWithSupportThreshold999999MinParticipation100AndMinApproval100InEarlyExecutionMode
        givenTokenBalancesAreInTheMagnitudeOf1018
    {
        // It early support criterion is sharp by 1 vote
        uint256 proposalId = _createDummyProposal(alice);
        assertFalse(plugin.isSupportThresholdReachedEarly(proposalId));

        vm.prank(alice);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertFalse(plugin.isMinParticipationReached(proposalId));

        vm.prank(bob);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertTrue(plugin.isSupportThresholdReachedEarly(proposalId));
    }

    function test_WhenTheNumberOfCastedVotesIsOneShyOf100Participation()
        external
        givenAnEdgeCaseWithSupportThreshold999999MinParticipation100AndMinApproval100InEarlyExecutionMode
        givenTokenBalancesAreInTheMagnitudeOf1018
    {
        // It participation criterion is sharp by 1 vote
        uint256 proposalId = _createDummyProposal(alice);

        vm.prank(alice);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertFalse(plugin.isMinParticipationReached(proposalId));

        vm.prank(carol);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertFalse(plugin.isMinParticipationReached(proposalId));

        vm.prank(bob);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertTrue(plugin.isMinParticipationReached(proposalId));
    }

    modifier givenTokenBalancesAreInTheMagnitudeOf106() {
        uint256 totalSupply = 10 ** 6;
        uint256 delta = 1; // 1 vote is 0.0001% of total supply
        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;
        uint256[] memory balances = new uint256[](2);
        balances[0] = totalSupply - delta;
        balances[1] = delta;

        (dao, plugin,,) = builder.withNewToken(holders, balances).build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        _;
    }

    function test_WhenTheNumberOfYesVotesIsOneShyOfEnsuringTheSupportThresholdCannotBeDefeated2()
        external
        givenAnEdgeCaseWithSupportThreshold999999MinParticipation100AndMinApproval100InEarlyExecutionMode
        givenTokenBalancesAreInTheMagnitudeOf106
    {
        // It early support criterion is sharp by 1 vote
        uint256 proposalId = _createDummyProposal(alice);
        assertFalse(plugin.isSupportThresholdReachedEarly(proposalId));

        vm.prank(alice);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertFalse(plugin.isSupportThresholdReachedEarly(proposalId));

        vm.prank(bob);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertTrue(plugin.isSupportThresholdReachedEarly(proposalId));
    }

    function test_WhenTheNumberOfCastedVotesIsOneShyOf100Participation2()
        external
        givenAnEdgeCaseWithSupportThreshold999999MinParticipation100AndMinApproval100InEarlyExecutionMode
        givenTokenBalancesAreInTheMagnitudeOf106
    {
        // It participation is not met with 1 vote missing
        uint256 proposalId = _createDummyProposal(alice);
        assertFalse(plugin.isMinParticipationReached(proposalId));

        vm.prank(alice);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertFalse(plugin.isMinParticipationReached(proposalId));

        vm.prank(bob);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        assertTrue(plugin.isMinParticipationReached(proposalId));
    }

    modifier givenExecutionCriteriaMultipleOrdersOfMagnitude() {
        _;
    }

    function _runMagnitudeTest(uint256 power) internal {
        uint256 baseUnit = 10 ** power;
        address[] memory holders = new address[](2);
        holders[0] = alice;
        holders[1] = bob;
        uint256[] memory balances = new uint256[](2);
        balances[0] = baseUnit * 5 + 1;
        balances[1] = baseUnit * 5;

        (dao, plugin,,) = new SimpleBuilder().withEarlyExecution().withNewToken(holders, balances).build();
        dao.grant(address(plugin), alice, plugin.CREATE_PROPOSAL_PERMISSION_ID());

        uint256 proposalId = _createDummyProposal(alice);

        vm.prank(alice);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        assertTrue(plugin.isSupportThresholdReached(proposalId));
        assertTrue(plugin.isMinParticipationReached(proposalId));
        assertTrue(plugin.isSupportThresholdReachedEarly(proposalId));
        assertTrue(plugin.canExecute(proposalId));

        vm.prank(bob);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.No, false);

        assertTrue(plugin.isSupportThresholdReached(proposalId));
        assertTrue(plugin.isMinParticipationReached(proposalId));
        assertTrue(plugin.isSupportThresholdReachedEarly(proposalId));
        assertTrue(plugin.canExecute(proposalId));
    }

    function test_WhenTestingWithAMagnitudeOf100() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(0);
    }

    function test_WhenTestingWithAMagnitudeOf101() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(1);
    }

    function test_WhenTestingWithAMagnitudeOf102() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(2);
    }

    function test_WhenTestingWithAMagnitudeOf103() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(3);
    }

    function test_WhenTestingWithAMagnitudeOf106() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(6);
    }

    function test_WhenTestingWithAMagnitudeOf1012() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(12);
    }

    function test_WhenTestingWithAMagnitudeOf1018() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(18);
    }

    function test_WhenTestingWithAMagnitudeOf1024() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(24);
    }

    function test_WhenTestingWithAMagnitudeOf1036() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(36);
    }

    function test_WhenTestingWithAMagnitudeOf1048() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(48);
    }

    function test_WhenTestingWithAMagnitudeOf1060() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(60);
    }

    function test_WhenTestingWithAMagnitudeOf1066() external givenExecutionCriteriaMultipleOrdersOfMagnitude {
        _runMagnitudeTest(66);
    }
}

contract MyTokenVoting is TokenVoting {
    using EnumerableSet for EnumerableSet.AddressSet;

    function getProposalMinApprovals(uint256 proposalId) public view returns (uint256) {
        return proposals[proposalId].minApprovalPower;
    }

    function excludedAccountsLength() public view returns (uint256) {
        return excludedAccounts.length();
    }
}
