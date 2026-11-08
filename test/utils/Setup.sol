// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { YToken } from "src/YToken.sol";
import { IYBVotingEscrow } from "src/interfaces/yb/IYBVotingEscrow.sol";
import { IYBGaugeController } from "src/interfaces/yb/IYBGaugeController.sol";
import { IYBTokenVoting, Action, IMajorityVoting, MajorityVotingBase } from "src/interfaces/yb/IYBTokenVoting.sol";
import { YB } from "src/utils/Constants.sol";

contract Setup is Test {
    uint256 public constant MAX_LOCK_TIME = 4 * 365 days;
    uint256 public mainnetFork;

    Locker public locker;
    Operator public operator;
    IERC20 public token;
    IYBVotingEscrow public escrow;
    IYBGaugeController public gaugeController;
    IYBTokenVoting public daoVoting;
    IERC20 public yToken;

    function setUp() public virtual {
        string memory mainnetRpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth.llamarpc.com"));
        mainnetFork = vm.createSelectFork(mainnetRpcUrl);

        token = IERC20(YB.TOKEN);
        escrow = IYBVotingEscrow(YB.VEYB);
        gaugeController = IYBGaugeController(YB.GAUGE_CONTROLLER);
        daoVoting = IYBTokenVoting(YB.DAO_VOTING);
        
        address predictedLockerAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        deal(address(token), predictedLockerAddress, 1e18);

        locker = new Locker(address(this), address(token), address(escrow));
        yToken = IERC20(payable(address(new YToken(address(locker), address(token), "Yearn YB Token", "yYB"))));
        operator = new Operator(payable(address(locker)), address(gaugeController), address(daoVoting), address(yToken));
        locker.setOperator(address(operator));

        // yToken should automatically be authorized as a locker, allowing users to call lock()
        assertTrue(operator.lockers(address(yToken)));

        // Voter power realization requires a 1s delay
        skip(1);
    }

    function createLock(address user, uint256 _amount, uint256 _unlockTime) public {
        // require(escrow.locked(user) == 0, "Lock already exists");
        deal(address(token), user, _amount);
        vm.startPrank(user);
        if (token.allowance(user, address(escrow)) < type(uint256).max) {
            token.approve(address(escrow), type(uint256).max);
        }
        escrow.create_lock(_amount, _unlockTime);
        vm.stopPrank();
        skip(1);
    }

    function isPermaLocked(address _locker) public view returns (bool) {
        (, uint256 end) = escrow.locked(_locker);
        if (end < block.timestamp) return false;
        if (end == type(uint256).max) return true;
        return false;
    }

    function toggleInfiniteLock(address _locker, bool _toggleMax) public {
        if (isPermaLocked(_locker) && _toggleMax) return;
        if (!isPermaLocked(_locker) && !_toggleMax) return;
        vm.prank(_locker);
        escrow.infinite_lock_toggle();
    }

    function increaseLock(address user, uint256 _amount) public {
        deal(address(token), user, _amount);
        vm.startPrank(user);
        if (token.allowance(user, address(escrow)) < _amount) {
            token.approve(address(escrow), _amount);
        }
        escrow.increase_amount(_amount);
        vm.stopPrank();
    }

    function createDaoProposal() public returns (uint256 proposalId) {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(operator),
            value: 0,
            data: ""
        });
        vm.prank(address(locker));
        proposalId = daoVoting.createProposal(
            bytes("Test Proposal"),
            actions,
            uint64(block.timestamp), // startTime
            uint64(block.timestamp + 7 days), // endTime
            bytes("")
        );
        skip(1);
    }

    function hasProposalPermissions() public view returns (bool) {
        address dao = daoVoting.dao();
        bytes32 permissionId = daoVoting.CREATE_PROPOSAL_PERMISSION_ID();
        return IYBTokenVoting(dao).isGranted(
            address(daoVoting),
            address(locker),
            permissionId,
            ""
        );
    }

    function grantCreateProposalPermission() public {
        if (hasProposalPermissions()) return;

        address dao = daoVoting.dao();
        bytes32 permissionId = daoVoting.CREATE_PROPOSAL_PERMISSION_ID();

        vm.prank(dao);
        IYBTokenVoting(dao).grant(
            address(daoVoting),
            address(locker),
            permissionId
        );
    }

    function getPastVotingPower(uint256 _ts) public view returns (uint256) {
        return escrow.getPastVotes(address(locker), _ts);
    }

    function getProposalInfo(uint256 _proposalId) public view returns (bool, bool, MajorityVotingBase.ProposalParameters memory, IMajorityVoting.Tally memory, Action[] memory, uint256) {
        (
            bool open, 
            bool executed, 
            MajorityVotingBase.ProposalParameters memory parameters, 
            IMajorityVoting.Tally memory tally, 
            Action[] memory actions, 
            uint256 allowFailureMap, 
        ) = daoVoting.getProposal(_proposalId);
        return (open, executed, parameters, tally, actions, allowFailureMap);
    }
}
