// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { BeaconDeposit } from "src/pol/BeaconDeposit.sol";
import { ERC165 } from "src/pol/interfaces/IERC165.sol";
import { IBeaconDeposit, IPOLErrors } from "src/pol/interfaces/IBeaconDeposit.sol";

contract BeaconDepositTest is Test {
    /// @dev The depositor address.
    address internal depositor = 0x20f33CE90A13a4b5E7697E3544c3083B8F8A51D4;

    /// @dev The validator public key.
    bytes internal VALIDATOR_PUBKEY = _create48Byte();

    /// @dev The withdrawal credentials that we will use.
    bytes internal WITHDRAWAL_CREDENTIALS = _credential(address(this));

    /// @dev The staking credentials that are right.
    bytes internal STAKING_CREDENTIALS = _credential(depositor);

    address internal operator = makeAddr("operator");

    address internal newOperator = makeAddr("newOperator");

    uint64 internal constant MIN_DEPOSIT_AMOUNT_IN_GWEI = 10_000 gwei;
    uint256 internal constant MIN_DEPOSIT_AMOUNT_IN_ETHER = 10_000 ether;

    /// @dev the deposit contract.
    BeaconDeposit internal depositContract;

    function setUp() public virtual {
        // Deposit MIN_DEPOSIT_AMOUNT_IN_ETHER to the depositor.
        vm.deal(depositor, MIN_DEPOSIT_AMOUNT_IN_ETHER);
        depositContract = new BeaconDeposit();
    }

    function test_SupportsInterface() public view {
        // Return true for the IBeaconDeposit interface.
        assertTrue(depositContract.supportsInterface(type(IBeaconDeposit).interfaceId));
        // Return true for the ERC165 interface.
        assertTrue(depositContract.supportsInterface(type(ERC165).interfaceId));
        // Return false for any other interface.
        assertFalse(depositContract.supportsInterface(bytes4(keccak256("not_supported"))));
    }

    function testFuzz_DepositsWrongPubKey(bytes memory pubKey) public {
        vm.assume(pubKey.length != 48);
        vm.expectRevert(IPOLErrors.InvalidPubKeyLength.selector);
        vm.prank(depositor);
        depositContract.deposit{ value: MIN_DEPOSIT_AMOUNT_IN_ETHER }(
            pubKey, STAKING_CREDENTIALS, _create96Byte(), operator
        );
    }

    function test_DepositWrongPubKey() public {
        testFuzz_DepositsWrongPubKey(bytes("wrong_public_key"));
    }

    function testFuzz_DepositWrongCredentials(bytes memory credentials) public {
        vm.assume(credentials.length != 32);

        vm.expectRevert(IPOLErrors.InvalidCredentialsLength.selector);
        vm.prank(depositor);
        depositContract.deposit{ value: MIN_DEPOSIT_AMOUNT_IN_ETHER }(
            _create48Byte(), credentials, _create96Byte(), operator
        );
    }

    function test_DepositWrongCredentials() public {
        testFuzz_DepositWrongCredentials(bytes("wrong_credentials"));
    }

    function test_DepositZeroOperator() public {
        vm.expectRevert(IPOLErrors.ZeroOperatorOnFirstDeposit.selector);
        vm.prank(depositor);
        depositContract.deposit{ value: MIN_DEPOSIT_AMOUNT_IN_ETHER }(
            VALIDATOR_PUBKEY, STAKING_CREDENTIALS, _create96Byte(), address(0)
        );
    }

    function testFuzz_DepositWrongMinAmount(uint256 amountInEther) public {
        amountInEther = _bound(amountInEther, 1, 9999);
        uint256 amountInGwei = amountInEther * 1 gwei;
        vm.deal(depositor, amountInGwei);
        vm.prank(depositor);
        vm.expectRevert(IPOLErrors.InsufficientDeposit.selector);
        depositContract.deposit{ value: amountInGwei }(
            VALIDATOR_PUBKEY, STAKING_CREDENTIALS, _create96Byte(), operator
        );
    }

    function test_DepositWrongAmount() public {
        testFuzz_DepositWrongMinAmount(MIN_DEPOSIT_AMOUNT_IN_ETHER - 1);
    }

    function testFuzz_DepositNotDivisibleByGwei(uint256 amount) public {
        amount = _bound(amount, MIN_DEPOSIT_AMOUNT_IN_GWEI + 1, uint256(type(uint64).max));
        vm.assume(amount % 1e9 != 0);
        vm.deal(depositor, amount);

        vm.prank(depositor);
        vm.expectRevert(IPOLErrors.DepositNotMultipleOfGwei.selector);
        depositContract.deposit{ value: amount }(VALIDATOR_PUBKEY, STAKING_CREDENTIALS, _create96Byte(), operator);
    }

    function test_DepositNotDivisibleByGwei() public {
        // 32 ether +1
        testFuzz_DepositNotDivisibleByGwei(MIN_DEPOSIT_AMOUNT_IN_GWEI + 1);
        // 32 ether -1
        testFuzz_DepositNotDivisibleByGwei(MIN_DEPOSIT_AMOUNT_IN_GWEI - 1);
    }

    function test_Deposit_FailsIfOperatorAlreadySet() public {
        test_Deposit();
        vm.deal(depositor, MIN_DEPOSIT_AMOUNT_IN_ETHER);
        vm.prank(depositor);
        vm.expectRevert(IPOLErrors.OperatorAlreadySet.selector);
        depositContract.deposit{ value: MIN_DEPOSIT_AMOUNT_IN_ETHER }(
            VALIDATOR_PUBKEY, STAKING_CREDENTIALS, _create96Byte(), operator
        );
    }

    function test_Deposit() public {
        vm.prank(depositor);
        vm.expectEmit(true, true, true, true);
        emit IBeaconDeposit.Deposit(
            VALIDATOR_PUBKEY, STAKING_CREDENTIALS, MIN_DEPOSIT_AMOUNT_IN_GWEI, _create96Byte(), 0
        );
        depositContract.deposit{ value: MIN_DEPOSIT_AMOUNT_IN_ETHER }(
            VALIDATOR_PUBKEY, STAKING_CREDENTIALS, _create96Byte(), operator
        );
        assertEq(depositContract.getOperator(VALIDATOR_PUBKEY), operator);
    }

    function testFuzz_DepositCount(uint256 count) public {
        count = _bound(count, 1, 100);
        vm.deal(depositor, MIN_DEPOSIT_AMOUNT_IN_ETHER * count);
        vm.startPrank(depositor);
        // First deposit with non-zero operator.
        depositContract.deposit{ value: MIN_DEPOSIT_AMOUNT_IN_ETHER }(
            VALIDATOR_PUBKEY, STAKING_CREDENTIALS, _create96Byte(), operator
        );
        uint64 depositCount = 1;
        for (uint256 i; i < count - 1; ++i) {
            vm.expectEmit(true, true, true, true);
            emit IBeaconDeposit.Deposit(
                VALIDATOR_PUBKEY, STAKING_CREDENTIALS, MIN_DEPOSIT_AMOUNT_IN_GWEI, _create96Byte(), depositCount
            );
            depositContract.deposit{ value: MIN_DEPOSIT_AMOUNT_IN_ETHER }(
                VALIDATOR_PUBKEY, STAKING_CREDENTIALS, _create96Byte(), address(0)
            );
            ++depositCount;
        }
        assertEq(depositContract.depositCount(), depositCount);
    }

    function testFuzz_RequestOperatorChange(address _newOperator) public {
        vm.assume(_newOperator != address(0));
        test_Deposit();
        vm.prank(operator);
        vm.expectEmit(true, true, true, true);
        emit IBeaconDeposit.OperatorChangeQueued(VALIDATOR_PUBKEY, _newOperator, operator, block.timestamp);
        depositContract.requestOperatorChange(VALIDATOR_PUBKEY, _newOperator);
        // Operator should not have changed yet.
        assertEq(depositContract.getOperator(VALIDATOR_PUBKEY), operator);
        (uint96 queuedTimestamp, address queuedOperator) = depositContract.queuedOperator(VALIDATOR_PUBKEY);
        assertEq(queuedOperator, _newOperator);
        assertEq(queuedTimestamp, block.timestamp);
    }

    function test_RequestOperatorChange() public {
        testFuzz_RequestOperatorChange(newOperator);
    }

    function test_RequestOperatorChange_FailsIfZeroAddress() public {
        test_Deposit();
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        depositContract.requestOperatorChange(VALIDATOR_PUBKEY, address(0));
    }

    function test_RequestOperatorChange_FailsIfNotCurrentOperator() public {
        test_Deposit();
        vm.prank(newOperator);
        vm.expectRevert(IPOLErrors.NotOperator.selector);
        depositContract.requestOperatorChange(VALIDATOR_PUBKEY, newOperator);
    }

    function test_CancelOperatorChange() public {
        test_RequestOperatorChange();
        vm.prank(operator);
        vm.expectEmit(true, true, true, true);
        emit IBeaconDeposit.OperatorChangeCancelled(VALIDATOR_PUBKEY);
        depositContract.cancelOperatorChange(VALIDATOR_PUBKEY);
        assertEq(depositContract.getOperator(VALIDATOR_PUBKEY), operator);
        (uint96 queuedTimestamp, address queuedOperator) = depositContract.queuedOperator(VALIDATOR_PUBKEY);
        assertEq(queuedOperator, address(0));
        assertEq(queuedTimestamp, 0);
    }

    function test_CancelOperatorChange_FailsIfNotCurrentOperator() public {
        testFuzz_RequestOperatorChange(newOperator);
        vm.prank(newOperator);
        vm.expectRevert(IPOLErrors.NotOperator.selector);
        depositContract.cancelOperatorChange(VALIDATOR_PUBKEY);
    }

    function test_AcceptOperatorChange_FailsIfNotNewOperator() public {
        testFuzz_RequestOperatorChange(newOperator);
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.NotNewOperator.selector);
        depositContract.acceptOperatorChange(VALIDATOR_PUBKEY);
    }

    function test_AcceptOperatorChange_FailsIfNotQueued() public {
        test_Deposit();
        vm.prank(newOperator);
        // In this case newOperator will be zero address as nothing queued
        // Hence msg.sender will not be equal to newOperator i.e zero address
        // Therefore the check in the function will revert with NotNewOperator
        vm.expectRevert(IPOLErrors.NotNewOperator.selector);
        depositContract.acceptOperatorChange(VALIDATOR_PUBKEY);
    }

    function testFuzz_AcceptOperatorChange_FailsIfNotEnoughTime(uint256 timeElapsed) public {
        timeElapsed = _bound(timeElapsed, 0, 1 days - 1);
        testFuzz_RequestOperatorChange(newOperator);
        vm.warp(block.timestamp + timeElapsed);
        vm.prank(newOperator);
        vm.expectRevert(IPOLErrors.NotEnoughTime.selector);
        depositContract.acceptOperatorChange(VALIDATOR_PUBKEY);
    }

    function test_AcceptOperatorChange_FailsIfNotEnoughTime() public {
        testFuzz_AcceptOperatorChange_FailsIfNotEnoughTime(1 days - 1);
    }

    function test_AcceptOperatorChange() public {
        testFuzz_RequestOperatorChange(newOperator);
        // Warp time to after the delay.
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(newOperator);
        vm.expectEmit(true, true, true, true);
        emit IBeaconDeposit.OperatorUpdated(VALIDATOR_PUBKEY, newOperator, operator);
        depositContract.acceptOperatorChange(VALIDATOR_PUBKEY);
        assertEq(depositContract.getOperator(VALIDATOR_PUBKEY), newOperator);
        (uint96 queuedTimestamp, address queuedOperator) = depositContract.queuedOperator(VALIDATOR_PUBKEY);
        assertEq(queuedOperator, address(0));
        assertEq(queuedTimestamp, 0);
    }

    function _credential(address addr) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), addr);
    }

    function _create96Byte() internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32("32"), bytes32("32"), bytes32("32"));
    }

    function _create48Byte() internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32("32"), bytes16("16"));
    }
}
