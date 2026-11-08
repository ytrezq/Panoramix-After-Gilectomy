// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";
import { Test }      from "../../modules/forge-std/src/Test.sol";

import { ILoanManager } from "../../contracts/interfaces/ILoanManager.sol";

import { LoanManagerStorage } from "../../contracts/LoanManagerStorage.sol";

// TODO: Eventually propose this to `forge-std`.
contract Spied is Test {

    bool internal assertCalls;
    bool internal captureCall;

    uint256 callCount;

    bytes[] internal calls;

    modifier spied() {
        if (captureCall) {
            calls.push(msg.data);
            captureCall = false;
        } else {
            if (assertCalls) {
                assertEq(msg.data, calls[callCount++], "Unexpected call spied");
            }

            _;
        }
    }

    function __expectCall() public {
        assertCalls = true;
        captureCall = true;
    }

}

contract MockFactory is Spied {

    address public mapleGlobals;

    mapping(address => bool) public isInstance;

    function upgradeInstance(uint256 version_, bytes calldata arguments_) external spied {}

    function __setMapleGlobals(address mapleGlobals_) external {
        mapleGlobals = mapleGlobals_;
    }

    function __setIsInstance(address instance_, bool isInstance_) external {
        isInstance[instance_] = isInstance_;
    }

}

contract MockGlobals {

    bool internal _canDeploy;
    bool internal _isBorrower;
    bool internal _isFunctionPaused;
    bool internal _isValidScheduledCall;

    address public governor;
    address public mapleTreasury;
    address public securityAdmin;

    bool public protocolPaused;

    mapping(address => uint256) public getLatestPrice;
    mapping(address => uint256) public platformManagementFeeRate;

    mapping(bytes32 => mapping(address => bool)) public isInstanceOf;

    function canDeploy(address) external view returns (bool canDeploy_) {
        canDeploy_ = _canDeploy;
    }

    function isBorrower(address) external view returns (bool isBorrower_) {
        isBorrower_ = _isBorrower;
    }

    function isFunctionPaused(bytes4) external view returns (bool isFunctionPaused_) {
        isFunctionPaused_ = _isFunctionPaused;
    }

    function isValidScheduledCall(address, address, bytes32, bytes calldata) external view returns (bool isValid_) {
        isValid_ = _isValidScheduledCall;
    }

    function setMapleTreasury(address treasury_) external {
        mapleTreasury = treasury_;
    }

    function setPlatformManagementFeeRate(address poolManager_, uint256 platformManagementFeeRate_) external {
        platformManagementFeeRate[poolManager_] = platformManagementFeeRate_;
    }

    function unscheduleCall(address, bytes32, bytes calldata) external pure {}

    function __setCanDeploy(bool canDeploy_) external {
        _canDeploy = canDeploy_;
    }

    function __setFunctionPaused(bool paused_) external {
        _isFunctionPaused = paused_;
    }

    function __setGovernor(address governor_) external {
        governor = governor_;
    }

    function __setIsBorrower(bool isBorrower_) external {
        _isBorrower = isBorrower_;
    }

    function __setInstanceOf(bytes32 instanceType_, address instance_, bool isInstance_) external {
        isInstanceOf[instanceType_][instance_] = isInstance_;
    }

    function __setIsValidScheduledCall(bool isValid_) external {
        _isValidScheduledCall = isValid_;
    }

    function __setProtocolPaused(bool paused_) external {
        protocolPaused = paused_;
    }

    function __setSecurityAdmin(address securityAdmin_) external {
        securityAdmin = securityAdmin_;
    }

}

contract MockLoan is Spied {

    address public factory;
    address public borrower;

    bytes32 public refinanceCommitment;

    uint40 public dateImpaired;
    uint40 public datePaid;
    uint40 public dateFunded;
    uint40 public defaultDate;
    uint40 public paymentDueDate;

    uint256 public paymentInterval;
    uint256 public principal;

    uint256 _fundsLent;

    mapping(uint256 => uint256) _interest;
    mapping(uint256 => uint256) _lateInterest;

    uint256 _platformServiceFee;

    function callPrincipal(uint256) external virtual spied returns (uint40 paymentDueDate_, uint40 defaultDate_) {
        ( paymentDueDate_, defaultDate_ ) = ( paymentDueDate, defaultDate );
    }

    function fund() public virtual spied returns (uint256 fundsLent_, uint40 paymentDueDate_, uint40 defaultDate_) {
        ( fundsLent_, paymentDueDate_, defaultDate_ ) = ( _fundsLent, paymentDueDate, defaultDate );
    }

    function impair() external virtual spied returns (uint40 paymentDueDate_, uint40 defaultDate_) {
        ( paymentDueDate_, defaultDate_ ) = ( paymentDueDate, defaultDate );
    }

    function isImpaired() external view returns (bool isImpaired_) {
        isImpaired_ = dateImpaired != 0;
    }

    function getPaymentBreakdown(uint256 timestamp_)
        external view
        returns (
            uint256 calledPrincipal_,
            uint256 interest_,
            uint256 lateInterest_,
            uint256 delegateServiceFee_,
            uint256 platformServiceFee_
        )
    {
        timestamp_;

        (
            calledPrincipal_,
            interest_,
            lateInterest_,
            delegateServiceFee_,
            platformServiceFee_
        ) = ( 0, _interest[timestamp_], _lateInterest[timestamp_], 0, _platformServiceFee );
    }

    function proposeNewTerms(address refinancer_, uint256 deadline_, bytes[] calldata calls_)
        external virtual spied returns (bytes32 refinanceCommitment_)
    {
        refinancer_; deadline_; calls_;

        refinanceCommitment_ = refinanceCommitment;
    }

    function rejectNewTerms(address refinancer_, uint256 deadline_, bytes[] calldata calls_)
        external virtual spied returns (bytes32 refinanceCommitment_)
    {
        refinancer_; deadline_; calls_;

        refinanceCommitment_ = refinanceCommitment;
    }

    function removeCall() external virtual spied returns (uint40 paymentDueDate_, uint40 defaultDate_) {
        ( paymentDueDate_, defaultDate_) = ( paymentDueDate, defaultDate );
    }

    function repossess(address destination_) external virtual spied returns (uint256 fundsRepossessed_) {}

    function removeImpairment() external virtual spied returns (uint40 paymentDueDate_, uint40 defaultDate_) {
        ( paymentDueDate_, defaultDate_ ) = ( paymentDueDate, defaultDate );
    }

    function __setBorrower(address borrower_) external {
        borrower = borrower_;
    }

    function __setDateFunded(uint256 dateFunded_) external {
        dateFunded = uint40(dateFunded_);
    }

    function __setDateImpaired(uint256 dateImpaired_) external {
        dateImpaired = uint40(dateImpaired_);
    }

    function __setDatePaid(uint256 datePaid_) external {
        datePaid = uint40(datePaid_);
    }

    function __setDefaultDate(uint256 defaultDate_) external {
        defaultDate = uint40(defaultDate_);
    }

    function __setFactory(address factory_) external {
        factory = factory_;
    }

    function __setFundsLent(uint256 fundsLent_) external {
        _fundsLent = fundsLent_;
    }

    function __setInterest(uint256 timestamp_, uint256 interest_) external {
        _interest[timestamp_] = interest_;
    }

    function __setLateInterest(uint256 timestamp_, uint256 lateInterest_) external {
        _lateInterest[timestamp_] = lateInterest_;
    }

    function __setPaymentDueDate(uint256 paymentDueDate_) external {
        paymentDueDate = uint40(paymentDueDate_);
    }

    function __setPaymentInterval(uint256 paymentInterval_) external {
        paymentInterval = paymentInterval_;
    }

    function __setPlatformServiceFee(uint256 platformServiceFee_) external {
        _platformServiceFee = platformServiceFee_;
    }

    function __setPrincipal(uint256 principal_) external {
        principal = principal_;
    }

    function __setRefinanceCommitment(bytes32 refinanceCommitment_) external {
        refinanceCommitment = refinanceCommitment_;
    }

}

contract MockReenteringLoan is MockLoan {

    function fund() public override returns (uint256 fundsLent_, uint40 paymentDueDate_, uint40 defaultDate_) {
        ILoanManager(msg.sender).fund(address(this));
        ( fundsLent_, paymentDueDate_, defaultDate_ ) = super.fund();
    }

}

contract MockLoanFactory {

    address public mapleGlobals;

    mapping(address => bool) public isLoan;

    function __setMapleGlobals(address globals_) external {
        mapleGlobals = globals_;
    }

    function __setIsLoan(address loan_, bool isLoan_) external {
        isLoan[loan_] = isLoan_;
    }

}

contract MockPoolManager is Spied {

    address public asset;
    address public factory;
    address public pool;
    address public poolDelegate;

    bool public hasSufficientCover;

    uint256 public delegateManagementFeeRate;

    function requestFunds(address destination_, uint256 principal_) external pure {}

    function setDelegateManagementFeeRate(uint256 delegateManagementFeeRate_) external {
        delegateManagementFeeRate = delegateManagementFeeRate_;
    }

    function __setAsset(address asset_) external {
        asset = asset_;
    }

    function __setFactory(address factory_) external {
        factory = factory_;
    }

    function __setHasSufficientCover(bool hasSufficientCover_) external {
        hasSufficientCover = hasSufficientCover_;
    }

    function __setPool(address pool_) external {
        pool = pool_;
    }

    function __setPoolDelegate(address poolDelegate_) external {
        poolDelegate = poolDelegate_;
    }

}

contract MockRevertingERC20 {

    function approve(address, uint256) external pure returns (bool success_) {
        success_ = false;
        require(false);
    }

}
