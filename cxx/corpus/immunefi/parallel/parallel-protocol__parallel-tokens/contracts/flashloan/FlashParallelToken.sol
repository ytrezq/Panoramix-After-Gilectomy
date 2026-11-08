// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITokenP} from "../interfaces/ITokenP.sol";
import {CommonErrorsLib} from "../libraries/CommonErrorsLib.sol";
import {PercentageMathLib} from "../libraries/PercentageMathLib.sol";

import {FlashLoan_EventsLib as EventsLib} from "./EventsLib.sol";
import {FlashLoan_ErrorsLib as ErrorsLib} from "./ErrorsLib.sol";

/// @title FlashParallelToken
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Contract to take flash loans on top of Parallel Tokens
contract FlashParallelToken is
    IERC3156FlashLender,
    AccessManagedUpgradeable,
    ReentrancyGuardTransientUpgradeable,
    UUPSUpgradeable
{
    using PercentageMathLib for uint256;
    using SafeERC20 for IERC20;

    /// @notice Success message received when calling a `FlashBorrower` contract
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    //-------------------------------------------
    // Storage
    //-------------------------------------------

    /// @notice Struct encoding for a given token the parameters
    struct TokenData {
        // Maximum amount borrowable for this token
        uint256 maxBorrowable;
        // Flash loan fee taken by the protocol for a flash loan on this token (in basic point)
        uint16 feesRate;
        // Whether the token flash loan is active
        bool isActive;
    }

    /// @notice Address of the recipient of the flash loan fee
    address public flashLoanFeeRecipient;

    /// @notice Maps a token to the data and parameters for flash loans
    mapping(address => TokenData) public tokenMap;

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /// @notice Initializes the contract
    /// @param _accessManager Access manager address
    function initialize(address _accessManager, address _flashLoanFeeRecipient) public initializer {
        if (address(_accessManager) == address(0)) revert CommonErrorsLib.AddressZero();
        if (address(_flashLoanFeeRecipient) == address(0)) revert CommonErrorsLib.AddressZero();
        __UUPSUpgradeable_init();
        __ReentrancyGuardTransient_init();
        __AccessManaged_init(_accessManager);
        flashLoanFeeRecipient = _flashLoanFeeRecipient;
    }

    //-------------------------------------------
    // Modifiers
    //-------------------------------------------

    /// @notice Checks whether a given token has been initialized in this contract
    /// @param token token to check
    /// @dev To check whether a token has been initialized, we just need to check whether its associated
    /// `treasury` address is not null in the `tokenMap`. This is what's checked in the `CoreBorrow` contract
    /// when adding support for a token
    modifier onlyActivetoken(address token) {
        require(tokenMap[token].isActive, ErrorsLib.UnsupportedToken());
        _;
    }

    //-------------------------------------------
    // ERC3156 Spec
    //-------------------------------------------

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 amount) external view onlyActivetoken(token) returns (uint256) {
        return _flashFee(token, amount);
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) external view returns (uint256) {
        // It will be 0 anyway if the token was not added
        return tokenMap[token].isActive ? tokenMap[token].maxBorrowable: 0;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant onlyActivetoken(token) returns (bool) {
        uint256 fee = _flashFee(token, amount);
        if (amount > tokenMap[token].maxBorrowable) revert ErrorsLib.TooBigAmount();
        ITokenP(token).mint(address(receiver), amount);
        if (receiver.onFlashLoan(msg.sender, token, amount, fee, data) != CALLBACK_SUCCESS)
            revert ErrorsLib.InvalidReturnMessage();
        // Token must be an TokenP here so normally no need to use `safeTransferFrom`, but out of safety
        // and in case governance whitelists an TokenP which does not have a correct implementation, we prefer
        // to use `safeTransferFrom` here
        IERC20(token).safeTransferFrom(address(receiver), address(this), amount + fee);
        ITokenP(token).burnSelf(amount, address(this));
        emit EventsLib.FlashLoan(token, amount, receiver);
        return true;
    }

    /// @notice Internal function to compute the fee induced for taking a flash loan of `amount` of `token`
    /// @param token The loan currency
    /// @param amount The amount of tokens lent
    /// @dev This function will revert if the `token` requested is not whitelisted here
    function _flashFee(address token, uint256 amount) internal view returns (uint256) {
        return amount.percentMul(tokenMap[token].feesRate);
    }

    //-------------------------------------------
    // Treasury Only Function
    //-------------------------------------------

    /// @notice Accrues interest to the fee recipient for a given list of tokens
    /// @param tokens List of addresses of tokens to accrue interest for
    /// @return balances Amounts of interest accrued
    function accrueInterestToFeeRecipient(address[] calldata tokens) external returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 balance= token.balanceOf(address(this));
            balances[i]=balance;
            token.safeTransfer(flashLoanFeeRecipient, balance);
        }
    }

    //-------------------------------------------
    // RestrictedFunction
    //-------------------------------------------

    /// @notice Sets the parameters for a given token
    /// @param _token token to change the parameters for
    /// @param _feesRate New flash loan fee for this token (in basic point)
    /// @param _maxBorrowable Maximum amount that can be borrowed in a single flash loan
    /// @dev Setting a `maxBorrowable` parameter equal to 0 is a way to pause the functionality
    /// @dev Parameters can only be modified for whitelisted tokens
    function setFlashLoanParameters(
        address _token,
        uint16 _feesRate,
        uint256 _maxBorrowable,
        bool _isActive
    ) external restricted {
        if (_feesRate > PercentageMathLib.PERCENTAGE_FACTOR) revert ErrorsLib.MaxFeesRateExceeded();
        tokenMap[_token] = TokenData({
            feesRate: _feesRate,
            maxBorrowable: _maxBorrowable,
            isActive: _isActive
        });
        emit EventsLib.FlashLoanParametersUpdated(_token, _feesRate, _maxBorrowable, _isActive);
    }

    /// @notice Sets the address of the recipient of the flash loan fee
    /// @param _newFlashLoanFeeRecipient New flash loan fee recipient
    function setFlashLoanFeeRecipient(address _newFlashLoanFeeRecipient) external restricted {
        if (_newFlashLoanFeeRecipient == address(0)) revert CommonErrorsLib.AddressZero();
        flashLoanFeeRecipient = _newFlashLoanFeeRecipient;
        emit EventsLib.FlashLoanFeeRecipientUpdated(_newFlashLoanFeeRecipient);
    }

    /// @notice Toggles the active status of a given token
    /// @param _token token to toggle the active status for
    function toggleActiveToken(address _token) external restricted {
        tokenMap[_token].isActive = !tokenMap[_token].isActive;
        emit EventsLib.ActiveTokenToggled(_token, tokenMap[_token].isActive);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override restricted {}
}
