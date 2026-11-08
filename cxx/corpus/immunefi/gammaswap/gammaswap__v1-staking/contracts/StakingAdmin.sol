// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/ILoanTracker.sol";
import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IVester.sol";
import "./interfaces/IStakingAdmin.sol";
import "./interfaces/IRestrictedToken.sol";
import "./interfaces/IBeaconProxyFactory.sol";

/// @title StakingAdmin abstract contract
/// @author Simon Mall
/// @notice Admin functions for StakingRouter contract
abstract contract StakingAdmin is IStakingAdmin, Ownable2Step, Initializable, UUPSUpgradeable {
    using GammaSwapLibrary for address;
    using ERC165Checker for address;

    address public immutable factory;
    address public immutable manager;

    address public override gs;
    address public override esGs;
    address public override esGsb;
    address public override bnGs;
    address public override feeRewardToken;

    bool public gsTokensInitialized;

    // Factories
    address private loanTrackerFactory;
    address private rewardTrackerFactory;
    address private feeTrackerFactory;
    address private rewardDistributorFactory;
    address private bonusDistributorFactory;
    address private vesterFactory;
    address private vesterNoReserveFactory;

    uint256 public constant VESTING_DURATION = 30 * 24 * 60 * 60;
    uint256 public POOL_VESTING_DURATION = 365 * 24 * 60 * 60;

    AssetCoreTracker internal _coreTracker;
    mapping(address => mapping(address => AssetPoolTracker)) internal _poolTrackers;

    constructor(address _factory, address _manager) {
        if (_factory == address(0) || _manager == address(0)) revert InvalidConstructor();

        factory = _factory;
        manager = _manager;
    }

    /// @inheritdoc IStakingAdmin
    function initialize(
        address _loanTrackerFactory,
        address _rewardTrackerFactory,
        address _feeTrackerFactory,
        address _rewardDistributorFactory,
        address _bonusDistributorFactory,
        address _vesterFactory,
        address _vesterNoReserveFactory) external override virtual initializer {
        if (_loanTrackerFactory == address(0) || _rewardTrackerFactory == address(0) || _feeTrackerFactory == address(0) ||
            _rewardDistributorFactory == address(0) || _bonusDistributorFactory == address(0) || _vesterFactory == address(0) ||
            _vesterNoReserveFactory == address(0)) {
            revert MissingBeaconProxyFactory();
        }

        _transferOwnership(msg.sender);
        POOL_VESTING_DURATION = 365 * 24 * 60 * 60;

        loanTrackerFactory = _loanTrackerFactory;
        rewardTrackerFactory = _rewardTrackerFactory;
        feeTrackerFactory = _feeTrackerFactory;
        rewardDistributorFactory = _rewardDistributorFactory;
        bonusDistributorFactory = _bonusDistributorFactory;
        vesterFactory = _vesterFactory;
        vesterNoReserveFactory = _vesterNoReserveFactory;
    }

    /// @inheritdoc IStakingAdmin
    function initializeGSTokens(address _gs, address _esGs, address _esGsb, address _bnGs, address _feeRewardToken) external override virtual onlyOwner {
        if(gsTokensInitialized) revert GSTokensAlreadySet();

        if (_gs == address(0) || _esGs == address(0) || _esGsb == address(0) || _bnGs == address(0) || _feeRewardToken == address(0)) {
            revert MissingGSTokenParameter();
        }

        if (IRestrictedToken(_esGs).tokenType() != IRestrictedToken.TokenType.ESCROW ||
            IRestrictedToken(_esGsb).tokenType() != IRestrictedToken.TokenType.ESCROW ||
            IRestrictedToken(_bnGs).tokenType() != IRestrictedToken.TokenType.BONUS) {
            revert InvalidRestrictedToken();
        }

        gsTokensInitialized = true;

        gs = _gs;
        esGsb = _esGsb;
        esGs = _esGs;
        bnGs = _bnGs;
        feeRewardToken = _feeRewardToken;

        _coreTracker.rewardTracker = address(0);
        _coreTracker.rewardDistributor = address(0);
        _coreTracker.loanRewardTracker = address(0);
        _coreTracker.loanRewardDistributor = address(0);
        _coreTracker.bonusTracker = address(0);
        _coreTracker.bonusDistributor = address(0);
        _coreTracker.feeTracker = address(0);
        _coreTracker.feeDistributor = address(0);
        _coreTracker.vester = address(0);
        _coreTracker.loanVester = address(0);
    }


    /// @inheritdoc IStakingAdmin
    function coreTracker() external override virtual view returns(address rewardTracker, address rewardDistributor,
        address loanRewardTracker, address loanRewardDistributor, address bonusTracker, address bonusDistributor,
        address feeTracker, address feeDistributor, address vester, address loanVester) {
        rewardTracker = _coreTracker.rewardTracker;  // Track GS + esGS
        rewardDistributor = _coreTracker.rewardDistributor;  // Reward esGS
        loanRewardTracker = _coreTracker.loanRewardTracker;  // Track esGSb
        loanRewardDistributor = _coreTracker.loanRewardDistributor;  // Reward esGSb
        bonusTracker = _coreTracker.bonusTracker; // Track GS + esGS + esGSb
        bonusDistributor = _coreTracker.bonusDistributor; // Reward bnGS
        feeTracker = _coreTracker.feeTracker; // Track GS + esGS + esGSb + bnGS(aka MP)
        feeDistributor = _coreTracker.feeDistributor; // Reward WETH
        vester = _coreTracker.vester; // Vest esGS -> GS (reserve GS or esGS or bnGS)
        loanVester = _coreTracker.loanVester; // Vest esGSb -> GS (without reserved tokens)
    }

    /// @inheritdoc IStakingAdmin
    function poolTrackers(address pool, address esToken) external override virtual view returns(address rewardTracker,
        address rewardDistributor, address loanRewardTracker, address loanRewardDistributor, address vester) {
        rewardTracker = _poolTrackers[pool][esToken].rewardTracker;
        rewardDistributor = _poolTrackers[pool][esToken].rewardDistributor;
        loanRewardTracker = _poolTrackers[pool][esToken].loanRewardTracker;
        loanRewardDistributor = _poolTrackers[pool][esToken].loanRewardDistributor;
        vester = _poolTrackers[pool][esToken].vester;
    }

    /// @inheritdoc IStakingAdmin
    function setPoolVestingPeriod(uint256 _poolVestingPeriod) external override virtual onlyOwner {
        require(_poolVestingPeriod > 0 && _poolVestingPeriod <= 365 days, "StakingAdmin: Invalid duration");
        POOL_VESTING_DURATION = _poolVestingPeriod;
    }

    /// @inheritdoc IStakingAdmin
    function setupGsStaking() external override virtual onlyOwner {
        if (_coreTracker.rewardTracker != address(0)) revert StakingContractsAlreadySet();

        address[] memory _depositTokens = new address[](2);
        _depositTokens[0] = gs;
        _depositTokens[1] = esGs;
        (address _rewardTracker, address _rewardDistributor) = _combineTrackerDistributor("Staked GS", "sGS", esGs, _depositTokens, 0, false, false);

        delete _depositTokens;
        _depositTokens = new address[](1);
        _depositTokens[0] = _rewardTracker;
        (address _bonusTracker, address _bonusDistributor) = _combineTrackerDistributor("Staked + Bonus GS", "sbGS", bnGs, _depositTokens, 0, false, true);

        delete _depositTokens;
        _depositTokens = new address[](2);
        _depositTokens[0] = _bonusTracker;
        _depositTokens[1] = bnGs;
        (address _feeTracker, address _feeDistributor) = _combineTrackerDistributor("Staked + Bonus + Fee GS", "sbfGS", feeRewardToken, _depositTokens, 0, true, false);

        address _vester = IBeaconProxyFactory(vesterFactory).deploy();
        IVester(_vester).initialize("Vested GS", "vGS", VESTING_DURATION, esGs, _feeTracker, gs, _rewardTracker);

        IRewardTracker(_rewardTracker).setHandler(_bonusTracker, true);
        IRewardTracker(_bonusTracker).setHandler(_feeTracker, true);
        IRewardTracker(_bonusTracker).setInPrivateClaimingMode(true);
        IRewardTracker(_feeTracker).setHandler(_vester, true);
        IVester(_vester).setHandler(address(this), true);
        IRestrictedToken(esGs).setHandler(_rewardTracker, true);
        IRestrictedToken(esGs).setHandler(_rewardDistributor, true);
        IRestrictedToken(esGs).setHandler(_vester, true);
        IRestrictedToken(bnGs).setHandler(_feeTracker, true);
        IRestrictedToken(bnGs).setHandler(_bonusTracker, true);
        IRestrictedToken(bnGs).setHandler(_bonusDistributor, true);

        _coreTracker.rewardTracker = _rewardTracker;
        _coreTracker.rewardDistributor = _rewardDistributor;
        _coreTracker.bonusTracker = _bonusTracker;
        _coreTracker.bonusDistributor = _bonusDistributor;
        _coreTracker.feeTracker = _feeTracker;
        _coreTracker.feeDistributor = _feeDistributor;
        _coreTracker.vester = _vester;

        emit CoreTrackerCreated(_rewardTracker, _rewardDistributor, _bonusTracker, _bonusDistributor, _feeTracker, _feeDistributor, _vester);
    }

    /// @inheritdoc IStakingAdmin
    function setupGsStakingForLoan() external override virtual onlyOwner {
        if (_coreTracker.loanRewardTracker != address(0)) revert StakingContractsAlreadySet();

        address[] memory _depositTokens = new address[](1);
        _depositTokens[0] = esGsb;
        (address _loanRewardTracker, address _loanRewardDistributor) = _combineTrackerDistributor("Staked GS Loan", "sGSb", esGsb, _depositTokens, 0, false, false);

        IRewardTracker(_coreTracker.bonusTracker).setDepositToken(_loanRewardTracker, true);
        IRewardTracker(_loanRewardTracker).setHandler(_coreTracker.bonusTracker, true);

        address _loanVester = IBeaconProxyFactory(vesterNoReserveFactory).deploy();
        IVester(_loanVester).initialize("Vested GS Borrowed", "vGSB", VESTING_DURATION, esGsb, address(0), gs, _loanRewardTracker);

        IVester(_loanVester).setHandler(address(this), true);
        IRestrictedToken(esGsb).setHandler(_loanRewardTracker, true);
        IRestrictedToken(esGsb).setHandler(_loanRewardDistributor, true);
        IRestrictedToken(esGsb).setHandler(_loanVester, true);

        _coreTracker.loanRewardTracker = _loanRewardTracker;
        _coreTracker.loanRewardDistributor = _loanRewardDistributor;
        _coreTracker.loanVester = _loanVester;

        emit CoreTrackerUpdated(_loanRewardTracker, _loanRewardDistributor, _loanVester);
    }

    /// @inheritdoc IStakingAdmin
    function setupPoolStaking(address _gsPool, address _esToken, address _claimableToken) external override virtual onlyOwner {
        if (IRestrictedToken(_esToken).tokenType() != IRestrictedToken.TokenType.ESCROW) revert InvalidRestrictedToken();

        if (_poolTrackers[_gsPool][_esToken].rewardTracker != address(0)) revert StakingContractsAlreadySet();

        address[] memory _depositTokens = new address[](1);
        _depositTokens[0] = _gsPool;
        (address _rewardTracker, address _rewardDistributor) = _combineTrackerDistributor("Staked GS LP", "sGSlp", _esToken, _depositTokens, 0, false, false);

        address _vester = IBeaconProxyFactory(vesterFactory).deploy();
        IVester(_vester).initialize("Vested Pool GS", "vpGS", POOL_VESTING_DURATION, _esToken, _rewardTracker, _claimableToken, _rewardTracker);

        IRewardTracker(_rewardTracker).setHandler(_vester, true);
        IVester(_vester).setHandler(address(this), true);
        IRestrictedToken(_esToken).setHandler(_rewardTracker, true);
        IRestrictedToken(_esToken).setHandler(_rewardDistributor, true);
        IRestrictedToken(_esToken).setHandler(_vester, true);

        _poolTrackers[_gsPool][_esToken].rewardTracker = _rewardTracker;
        _poolTrackers[_gsPool][_esToken].rewardDistributor = _rewardDistributor;
        _poolTrackers[_gsPool][_esToken].vester = _vester;

        _gsPool.safeApprove(_rewardTracker, type(uint256).max);

        emit PoolTrackerCreated(_gsPool, _rewardTracker, _rewardDistributor, _vester);
    }

    /// @inheritdoc IStakingAdmin
    function setupPoolStakingForLoan(address _gsPool, uint16 _refId) external override virtual onlyOwner {
        if(_poolTrackers[_gsPool][esGsb].loanRewardTracker != address(0)) revert StakingContractsAlreadySet();

        address[] memory _depositTokens = new address[](1);
        _depositTokens[0] = _gsPool;
        (address _loanRewardTracker, address _loanRewardDistributor) = _combineTrackerDistributor("Staked GS Loan", "sGSb", esGsb, _depositTokens, _refId, false, false);

        IRestrictedToken(esGsb).setHandler(_loanRewardTracker, true);
        IRestrictedToken(esGsb).setHandler(_loanRewardDistributor, true);

        _poolTrackers[_gsPool][esGsb].loanRewardTracker = _loanRewardTracker;
        _poolTrackers[_gsPool][esGsb].loanRewardDistributor = _loanRewardDistributor;

        emit PoolTrackerUpdated(_gsPool, _loanRewardTracker, _loanRewardDistributor);
    }

    /// @inheritdoc IStakingAdmin
    function execute(address _stakingContract, bytes calldata _data) external override virtual onlyOwner {
        if(
            !_stakingContract.supportsInterface(type(IRewardTracker).interfaceId) &&
            !_stakingContract.supportsInterface(type(ILoanTracker).interfaceId) &&
            !_stakingContract.supportsInterface(type(IRewardDistributor).interfaceId) &&
            !_stakingContract.supportsInterface(type(IVester).interfaceId)
        ) {
            revert InvalidExecute();
        }

        (bool success, bytes memory result) = _stakingContract.call(_data);
        if (!success) {
            if (result.length == 0) revert ExecuteFailed();
            assembly {
                revert(add(32, result), mload(result))
            }
        }
    }

    /// @dev Deploy reward tracker and distributor as a pair and bind them
    /// @param _name RewardTracker name as ERC20 token
    /// @param _symbol RewardTracker symbol as ERC20 token
    /// @param _rewardToken Reward token address
    /// @param _depositTokens Array of deposit tokens in RewardTracker
    /// @param _refId LoanObserver Id
    /// @param _isFeeTracker True if reward tracker should be FeeTracker
    /// @param _isBonusDistributor True if reward distributor should be BonusDistributor
    /// @return Reward tracker address
    /// @return Reward distributor address
    function _combineTrackerDistributor(
        string memory _name,
        string memory _symbol,
        address _rewardToken,
        address[] memory _depositTokens,
        uint16 _refId,
        bool _isFeeTracker,
        bool _isBonusDistributor
    ) private returns (address, address) {
        address tracker;
        if (_refId > 0) {
            tracker = IBeaconProxyFactory(loanTrackerFactory).deploy();
        } else if (_isFeeTracker) {
            tracker = IBeaconProxyFactory(feeTrackerFactory).deploy();
        } else {
            tracker = IBeaconProxyFactory(rewardTrackerFactory).deploy();
        }

        address distributor;
        if (_isBonusDistributor) {
            distributor = IBeaconProxyFactory(bonusDistributorFactory).deploy();
            IRewardDistributor(distributor).initialize(_rewardToken, tracker);
        } else {
            distributor = IBeaconProxyFactory(rewardDistributorFactory).deploy();
            IRewardDistributor(distributor).initialize(_rewardToken, tracker);
        }

        if (_refId > 0) {
            ILoanTracker(tracker).initialize(factory, _refId, manager, _name, _symbol,_depositTokens[0], distributor);
            ILoanTracker(tracker).setHandler(address(this), true);
        } else {
            IRewardTracker(tracker).initialize(_name, _symbol, _depositTokens, distributor);
            IRewardTracker(tracker).setHandler(address(this), true);
        }
        IRewardDistributor(distributor).updateLastDistributionTime();

        return (tracker, distributor);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}