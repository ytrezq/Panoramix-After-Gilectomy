// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { LoanManagerStorage } from "../../contracts/proxy/LoanManagerStorage.sol";

contract MockGlobals {

    bool internal _isBorrower;
    bool internal _isFunctionPaused;
    bool internal _isInstance;
    bool internal _isValidScheduledCall;

    address public governor;
    address public mapleTreasury;
    address public securityAdmin;

    bool public protocolPaused;

    mapping(address => bool) public isPoolDeployer;

    mapping(address => uint256) public getLatestPrice;
    mapping(address => uint256) public platformManagementFeeRate;

    constructor(address governor_) {
        governor = governor_;
    }

    function isBorrower(address) external view returns (bool isBorrower_) {
        isBorrower_ = _isBorrower;
    }

    function isFunctionPaused(bytes4) external view returns (bool isFunctionPaused_) {
        isFunctionPaused_ = _isFunctionPaused;
    }

    function isInstanceOf(bytes32, address) external view returns (bool isInstance_) {
        isInstance_ = _isInstance;
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

    function setValidPoolDeployer(address poolDeployer_, bool isValid_) external {
        isPoolDeployer[poolDeployer_] = isValid_;
    }

    function unscheduleCall(address, bytes32, bytes calldata) external {}

    function __setIsBorrower(bool isBorrower_) external {
        _isBorrower = isBorrower_;
    }

    function __setIsInstanceOf(bool isInstance_) external {
        _isInstance = isInstance_;
    }

    function __setIsValidScheduledCall(bool isValid_) external {
        _isValidScheduledCall = isValid_;
    }

    function __setFunctionPaused(bool paused_) external {
        _isFunctionPaused = paused_;
    }

    function __setSecurityAdmin(address securityAdmin_) external {
        securityAdmin = securityAdmin_;
    }

}

contract MockLoan {

    uint256 internal _unaccountedAmount;

    address public borrower;
    address public collateralAsset;
    address public factory;
    address public fundsAsset;

    bool public isImpaired;

    uint256 public collateral;
    uint256 public delegateServiceFee;
    uint256 public nextPaymentInterest;
    uint256 public nextPaymentDueDate;
    uint256 public nextPaymentLateInterest;
    uint256 public nextPaymentPrincipal;
    uint256 public originalNextPaymentDueDate;
    uint256 public paymentInterval;
    uint256 public paymentsRemaining;
    uint256 public platformServiceFee;
    uint256 public unimpairedPaymentDueDate;
    uint256 public principal;
    uint256 public principalRequested;
    uint256 public refinanceInterest;

    // Refinance Variables
    uint256 public refinanceNextPaymentInterest;
    uint256 public refinanceNextPaymentDueDate;
    uint256 public refinanceNextPaymentPrincipal;
    uint256 public refinancePaymentInterval;
    uint256 public refinancePrincipal;
    uint256 public refinancePrincipalRequested;

    constructor(address collateralAsset_, address fundsAsset_) {
        collateralAsset = collateralAsset_;
        fundsAsset      = fundsAsset_;
    }

    function acceptNewTerms(address, uint256, bytes[] calldata) external returns (bytes32 refinanceCommitment_) {
        nextPaymentInterest  = refinanceNextPaymentInterest;
        nextPaymentDueDate   = refinanceNextPaymentDueDate;
        nextPaymentPrincipal = refinanceNextPaymentPrincipal;
        paymentInterval      = refinancePaymentInterval;
        principal            = refinancePrincipal;
        principalRequested   = refinancePrincipalRequested;

        refinanceNextPaymentInterest  = 0;
        refinanceNextPaymentDueDate   = 0;
        refinanceNextPaymentPrincipal = 0;
        refinancePaymentInterval      = 0;
        refinancePrincipal            = 0;
        refinancePrincipalRequested   = 0;

        refinanceCommitment_ = 0; // Mock return
    }

    function fundLoan() external returns (uint256 fundsLent_) {
        // Do nothing
    }

    function getNextPaymentDetailedBreakdown() external view returns (
        uint256 principal_,
        uint256[3] memory interest_,
        uint256[2] memory fees_
    ) {
        principal_ = nextPaymentPrincipal;

        interest_[0] = nextPaymentInterest;
        interest_[1] = nextPaymentLateInterest;
        interest_[2] = refinanceInterest;

        fees_[0] = delegateServiceFee;
        fees_[1] = platformServiceFee;
    }

    function getUnaccountedAmount(address) external view returns (uint256 unaccountedAmount_) {
        unaccountedAmount_ = _unaccountedAmount;
    }

    function repossess(address destination_) external returns (uint256 collateralRepossessed_, uint256 fundsAssetRepossessed_) {
        collateralRepossessed_ = collateral;
        fundsAssetRepossessed_ = 0;
        MockERC20(collateralAsset).transfer(destination_, collateral);
    }

    function rejectNewTerms(
        address refinancer_,
        uint256 deadline_,
        bytes[] calldata calls_
    ) external returns (bytes32 refinanceCommitment_) {}

    function removeLoanImpairment() external {
        nextPaymentDueDate = unimpairedPaymentDueDate;
        delete unimpairedPaymentDueDate;

        isImpaired = false;
    }

    function setPendingLender(address lender_) external {
        // Do nothing
    }

    function acceptLender() external {
        // Do nothing
    }

    function impairLoan() external {
        unimpairedPaymentDueDate = nextPaymentDueDate;
        nextPaymentDueDate       = block.timestamp;
        isImpaired               = true;
    }

    function skim(address asset, address destination_) external returns (uint256 skimmed_) {}

    function __setBorrower(address borrower_) external {
        borrower = borrower_;
    }

    function __setCollateral(uint256 collateral_) external {
        collateral = collateral_;
    }

    function __setCollateralAsset(address collateralAsset_) external {
        collateralAsset = collateralAsset_;
    }

    function __setFactory(address factory_) external {
        factory = factory_;
    }

    function __setNextPaymentDueDate(uint256 nextPaymentDueDate_) external {
        nextPaymentDueDate = nextPaymentDueDate_;
    }

    function __setNextPaymentInterest(uint256 nextPaymentInterest_) external {
        nextPaymentInterest = nextPaymentInterest_;
    }

    function __setNextPaymentLateInterest(uint256 nextPaymentLateInterest_) external {
        nextPaymentLateInterest = nextPaymentLateInterest_;
    }

    function __setNextPaymentPrincipal(uint256 nextPaymentPrincipal_) external {
        nextPaymentPrincipal = nextPaymentPrincipal_;
    }

    function __setOriginalNextPaymentDueDate(uint256 originalNextPaymentDueDate_) external {
        originalNextPaymentDueDate = originalNextPaymentDueDate_;
    }

    function __setPaymentsRemaining(uint256 paymentsRemaining_) external {
        paymentsRemaining = paymentsRemaining_;
    }

    function __setPlatformServiceFee(uint256 platformServiceFee_) external {
        platformServiceFee = platformServiceFee_;
    }

    function __setPrincipal(uint256 principal_) external {
        principal = principal_;
    }

    function __setPrincipalRequested(uint256 principalRequested_) external {
        principalRequested = principalRequested_;
    }

    function __setRefinanceInterest(uint256 refinanceInterest_) external {
        refinanceInterest = refinanceInterest_;
    }

    function __setRefinancePrincipal(uint256 principal_) external {
        refinancePrincipal = principal_;
    }

    function __setRefinanceNextPaymentInterest(uint256 nextPaymentInterest_) external {
        refinanceNextPaymentInterest = nextPaymentInterest_;
    }

    function __setRefinanceNextPaymentDueDate(uint256 nextPaymentDueDate_) external {
        refinanceNextPaymentDueDate = nextPaymentDueDate_;
    }

    function __setUnaccountedAmount(uint256 unaccountedAmount_) external {
        _unaccountedAmount = unaccountedAmount_;
    }

}

contract MockLoanManagerMigrator is LoanManagerStorage {

    fallback() external {
        fundsAsset = abi.decode(msg.data, (address));
    }

}

contract MockLoanFactory {

    bool internal _isLoan;

    function isLoan(address ) external view returns (bool isLoan_) {
        isLoan_ = _isLoan;
    }

    function __setIsLoan(bool isLoan_) external {
        _isLoan = isLoan_;
    }

}

contract MockPoolManager {

    address public asset;
    address public factory;
    address public pool;
    address public poolDelegate;

    uint256 public delegateManagementFeeRate;

    function hasSufficientCover() external pure returns (bool hasSufficientCover_) {
        hasSufficientCover_ = true;
    }

    function requestFunds(address destination_, uint256 principal_) external {}

    function setDelegateManagementFeeRate(uint256 delegateManagementFeeRate_) external {
        delegateManagementFeeRate = delegateManagementFeeRate_;
    }

    function __setAsset(address asset_) external {
        asset = asset_;
    }

    function __setFactory(address factory_) external {
        factory = factory_;
    }

    function __setPool(address pool_) external {
        pool = pool_;
    }

    function __setPoolDelegate(address poolDelegate_) external {
        poolDelegate = poolDelegate_;
    }

}

contract MockLiquidator {

    uint256 public collateralRemaining;

    fallback() external {
        // Do nothing.
    }

}

contract MockLiquidatorFactory {

    function createInstance(bytes calldata, bytes32) external returns (address instance_) {
        instance_ = address(new MockLiquidator());
    }

}

contract MockFactory {

    bool internal _isInstance;

    function isInstance(address) external view returns (bool isInstance_) {
        isInstance_ = _isInstance;
    }

    function __setIsInstance(bool isInstance_) external {
        _isInstance = isInstance_;
    }

}
