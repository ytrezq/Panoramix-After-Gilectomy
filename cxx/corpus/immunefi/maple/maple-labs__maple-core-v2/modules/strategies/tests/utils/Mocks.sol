// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MapleBasicStrategyStorage } from "../../contracts/proxy/basicStrategy/MapleBasicStrategyStorage.sol";

contract MockAavePool {

    function supply(address, uint256, address, uint16) external {}

    function withdraw(address, uint256, address) external returns (uint256) {}

}

contract MockAaveRewardsController {

    uint256 public rewardAmount;

    function claimRewards(address[] calldata, uint256, address, address) external view returns (uint256) {
        return rewardAmount;
    }

    function __setRewardAmount(uint256 rewardAmount_) external {
        rewardAmount = rewardAmount_;
    }

}

contract MockAaveToken {

    constructor(address aavePool_, address underlyingAsset_, address incentivesController_) {
        POOL                     = aavePool_;
        UNDERLYING_ASSET_ADDRESS = underlyingAsset_;
        incentivesController     = incentivesController_;
    }

    address public incentivesController;
    address public POOL;
    address public UNDERLYING_ASSET_ADDRESS;

    uint256 internal currentTotalAssets;

    function balanceOf(address) external view returns (uint256 balanceOf_) {
        balanceOf_ = currentTotalAssets;
    }

    function getIncentivesController() external view returns (address incentivesController_) {
        incentivesController_ = incentivesController;
    }

    function __setCurrentTotalAssets(uint256 currentTotalAssets_) external {
        currentTotalAssets = currentTotalAssets_;
    }

    function __setUnderlyingAsset(address underlyingAsset_) external {
        UNDERLYING_ASSET_ADDRESS = underlyingAsset_;
    }

}

contract MockFactory {

    bool _isInstance;

    function isInstance(address) external view returns (bool isInstance_) {
        isInstance_ = _isInstance;
    }

    function __setIsInstance(bool isInstance_) external {
        _isInstance = isInstance_;
    }

}

contract MockGlobals {

    address public governor;
    address public operationalAdmin;
    address public securityAdmin;
    address public mapleTreasury;

    bool internal _canDeploy;
    bool internal _isFunctionPaused;
    bool internal _isInstance;
    bool internal _isValidScheduledCall;

    bool public protocolPaused;

    constructor (address governor_) {
        governor = governor_;
    }

    function canDeploy(address) external view returns (bool) {
        return _canDeploy;
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

    function unscheduleCall(address, bytes32, bytes calldata) external {}

    function __setCanDeploy(bool canDeploy_) external {
        _canDeploy = canDeploy_;
    }

    function __setFunctionPaused(bool paused_) external {
        _isFunctionPaused = paused_;
    }

    function __setIsInstanceOf(bool isInstance_) external {
        _isInstance = isInstance_;
    }

    function __setIsValidScheduledCall(bool isValid_) external {
        _isValidScheduledCall = isValid_;
    }

    function __setOperationalAdmin(address operationalAdmin_) external {
        operationalAdmin = operationalAdmin_;
    }

    function __setSecurityAdmin(address securityAdmin_) external {
        securityAdmin = securityAdmin_;
    }

    function __setMapleTreasury(address mapleTreasury_) external {
        mapleTreasury = mapleTreasury_;
    }

}

contract MockPool is MockERC20 {

    address public manager;
    address public poolDelegate;

    uint256 public sharePrice;

    MockERC20 _asset;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address asset_,
        address poolDelegate_
    )
        MockERC20(name_, symbol_, decimals_)
    {
        _asset = MockERC20(asset_);

        poolDelegate = poolDelegate_;
        sharePrice   = 1;
    }

    function asset() external view returns (address asset_) {
        asset_ = address(_asset);
    }

    function __setPoolManager(address poolManager_) external {
        manager = poolManager_;
    }

}

contract MockPoolManager {

    address public factory;
    address public globals;
    address public pool;
    address public poolDelegate;

    uint256 public totalAssets;
    uint256 public unrealizedLosses;

    constructor(address pool_, address poolDelegate_, address globals_) {
        globals      = globals_;
        pool         = pool_;
        poolDelegate = poolDelegate_;
    }

    function __setFactory(address factory_) external {
        factory = factory_;
    }

    function requestFunds(address, uint256) external { }

}

contract MockStrategiesMigrator is MapleBasicStrategyStorage {

    fallback() external {
        pool = abi.decode(msg.data, (address));
    }

}

contract MockVault {

    address public asset;

    uint256 public exchangeRate;

    mapping (address => uint256) public balances;

    constructor(address asset_) {
        asset = asset_;
    }

    function deposit(uint256 amount_, address) external view returns (uint256) {
        return amount_ * exchangeRate;
    }

    function redeem(uint256 amount_, address, address) external pure returns (uint256) {
        return amount_;
    }

    function withdraw(uint256 amount_, address, address) external pure returns (uint256) {
        return amount_;
    }

    function __setBalanceOf(address account_, uint256 amount_) external {
        balances[account_] = amount_;
    }

    function __setExchangeRate(uint256 exchangeRate_) external {
        exchangeRate = exchangeRate_;
    }

    function balanceOf(address account_) external view returns (uint256) {
        return balances[account_];
    }

    function convertToAssets(uint256 shares_) public view returns (uint256 assets_) {
        assets_ = shares_ * exchangeRate;
    }

    function maxWithdraw(address owner_) external view returns (uint256 maxAssets_) {
        return convertToAssets(balances[owner_]);
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets_) {
        assets_ = convertToAssets(shares);
    }

    function __setAsset(address asset_) external {
        asset = asset_;
    }

}

contract MockPSM {

    address public gem;
    address public usds;

    uint256 public to18ConversionFactor = 1e12;
    uint256 public tin;
    uint256 public tout;

    function buyGem(address, uint256 gemAmt) external pure returns (uint256 daiInWad) {
        return gemAmt;
    }

    function sellGem(address, uint256 gemAmt) external view returns (uint256 daiOutWad) {
        return gemAmt * 1e12 * (1e18 - tin) / 1e18;
    }

    function __setGem(address gem_) external {
        gem = gem_;
    }

    function __setUsds(address usds_) external {
        usds = usds_;
    }

    function __setTin(uint256 tin_) external {
        tin = tin_;
    }

    function __setTout(uint256 tout_) external {
        tout = tout_;
    }

}
