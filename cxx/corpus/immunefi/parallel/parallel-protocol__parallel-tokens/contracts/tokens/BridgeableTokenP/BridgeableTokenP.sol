// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { SendParam, MessagingFee, MessagingReceipt, OFTReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import { OFTMsgCodec } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ITokenP } from "contracts/interfaces/ITokenP.sol";
import { PercentageMathLib } from "contracts/libraries/PercentageMathLib.sol";
import {MathLib} from "contracts/libraries/MathLib.sol";
import {CommonErrorsLib} from "contracts/libraries/CommonErrorsLib.sol";
import "contracts/libraries/Constants.sol";

import {BridgeableTokenP_EventsLib as EventsLib} from "./EventsLib.sol";
import {BridgeableTokenP_ErrorsLib as ErrorsLib} from "./ErrorsLib.sol";

/// @title BridgeableTokenP
/// @author Cooper Labs
/// @notice Contract for Parallel Tokens on other chains than Ethereum mainnet
/// @dev This contract supports bridge tokens having a minting right on the stablecoin
/// (also referred to as the canonicalor the native token)
contract BridgeableTokenP is OFT, ReentrancyGuardTransient, Pausable {
    using SafeERC20 for IERC20;
    using PercentageMathLib for uint256;
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    //-------------------------------------------
    // Storage
    //-------------------------------------------
    
    /// @notice Permit calldata struct
    struct PermitCalldata {
        /// @notice The deadline of the permit.
        uint256 deadline;
        /// @notice The v value of the permit.
        uint8 v;
        /// @notice The r value of the permit.
        bytes32 r;
        /// @notice The s value of the permit.
        bytes32 s;
    }

    /// @notice Struct to initialize the contract
    struct ConfigParams {
        /// @notice Daily limit for credits
        uint256 dailyCreditLimit;
        /// @notice Global limit for credits
        uint256 globalCreditLimit;
        /// @notice Daily limit for debits
        uint256 dailyDebitLimit;
        /// @notice Global limit for debits
        uint256 globalDebitLimit;
        /// @notice Address of the fees recipient
        address feesRecipient;
        /// @notice Fees rate in basic point
        uint16 feesRate;
        /// @notice Whether the contract is in isolate mode
        bool isIsolateMode;
    }

    /// @notice The principalToken that can be minted and burned.
    IERC20 private immutable principalToken;
    /// @notice Limit the bridge to send more tokens than it had received.
    /// @dev If true, the bridge can't send more tokens than it had received (creditDebitBalance > 0).
    bool private isIsolateMode;
    /// @notice The fees recipient address.
    address private feesRecipient;
    /// @notice The fees rate in basic point.
    uint16 private feesRate;
    /// @notice Track the difference between credits and debits.
    /// @dev If amount < 0, it means debits exceed credits.
    int256 private creditDebitBalance;
    /// @notice The daily limit of PrincipalToken allowed to bridge TO this chain.
    uint256 private dailyCreditLimit;
    /// @notice The global limit of PrincipalToken allowed to bridge TO this chain.
    uint256 private globalCreditLimit;
    /// @notice The daily limit of PrincipalToken allowed to bridge FROM this chain.
    uint256 private dailyDebitLimit;
    /// @notice The global limit of PrincipalToken allowed to bridge FROM this chain.
    int256 private globalDebitLimit;
    /// @notice Track the daily credit amount of PrincipalToken.
    mapping(uint256 day => uint256 amount) private dailyCreditAmount;
    /// @notice Track the daily debit amount of PrincipalToken.
    mapping(uint256 day => uint256 amount) private dailyDebitAmount;
    

  
    //-------------------------------------------
    // Constructor
    //-------------------------------------------

     /// @notice Constructor for the OFT contract.
    /// @param _name The name of the OFT.
    /// @param _symbol The symbol of the OFT.
    /// @param _principalToken The principalToken address.
    /// @param _lzEndpoint The LayerZero endpoint address.
    /// @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
    /// @param _config The configuration parameters for the OFT.
    constructor(
        string memory _name,
        string memory _symbol,
        address _principalToken,
        address _lzEndpoint,
        address _delegate,
        ConfigParams memory _config
    ) Ownable(_delegate) OFT(_name, _symbol, _lzEndpoint, _delegate) {
        if (_principalToken == address(0)) revert CommonErrorsLib.AddressZero();
        principalToken = IERC20(_principalToken);
        _setFeesRate(_config.feesRate);
        _setDailyCreditLimit(_config.dailyCreditLimit);
        _setGlobalCreditLimit(_config.globalCreditLimit);
        _setDailyDebitLimit(_config.dailyDebitLimit);
        _setGlobalDebitLimit(_config.globalDebitLimit);
        _setIsolateMode(_config.isIsolateMode);
        _setFeesRecipient(_config.feesRecipient);
    }
    
    //-------------------------------------------
    // External functions
    //-------------------------------------------

    /// @notice Executes the send operation.
    /// @param _sendParam The parameters for the send operation.
    /// @param _fee The calculated fees for the send() operation.
    ///      - nativeFee: The native fees.
    ///      - lzTokenFee: The lzToken fees.
    /// @param _refundAddress The address to receive any excess funds.
    /// @return msgReceipt The receipt for the send operation.
    /// @return oftReceipt The OFT receipt information.
    ///
    /// @dev MessagingReceipt: LayerZero msg receipt
    ///  - guid: The unique identifier for the sent message.
    ///  - nonce: The nonce of the sent message.
    ///  - fees: The LayerZero fees incurred for the message.
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    )
        external
        payable
        override
        nonReentrant
        whenNotPaused
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        return _send(
            _sendParam,
            _fee,
            _refundAddress
        );
    }

    /// @notice Executes the send operation using permit.
    /// @param _sendParam The parameters for the send operation.
    /// @param _fee The calculated fees for the send() operation.
    ///      - nativeFee: The native fees.
    ///      - lzTokenFee: The lzToken fees.
    /// @param _permit The permit calldata.
    /// @param _refundAddress The address to receive any excess funds.
    /// @return msgReceipt The receipt for the send operation.
    /// @return oftReceipt The OFT receipt information.
    ///
    /// @dev MessagingReceipt: LayerZero msg receipt
    ///  - guid: The unique identifier for the sent message.
    ///  - nonce: The nonce of the sent message.
    ///  - fees: The LayerZero fees incurred for the message.
    function sendWithPermit(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        PermitCalldata calldata _permit,
        address _refundAddress
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        // @dev using try catch to avoid reverting the transaction in case of front-running
        try IERC20Permit(address(principalToken)).permit(msg.sender, address(this), _sendParam.amountLD, _permit.deadline, _permit.v, _permit.r, _permit.s) { }
            catch { }
        return _send(
            _sendParam,
            _fee,
            _refundAddress
        );
    }

    /// @notice Allow user to swap OFT token to principalToken if the amount is within the mint limit.
    /// @dev when the user swap OFT token to principalToken, the OFT token will be burned and the principalToken will be
    /// transferred or minted to the user.
    /// @param _to The address to credit the principalToken to.
    /// @param _amount The amount of OFT token to swap.
    function swapLzTokenToPrincipalToken(address _to, uint256 _amount) external nonReentrant whenNotPaused returns (uint256) {
        if (_to == address(0)) revert CommonErrorsLib.AddressZero();

        uint256 totalPrincipalTokenAmountToCredit = _calculatePrincipalTokenAmountToCredit(_amount);
        if (totalPrincipalTokenAmountToCredit == 0) revert ErrorsLib.NothingToSwap();

        _burn(msg.sender, totalPrincipalTokenAmountToCredit);

        /// @dev Update the daily usage and the creditDebitBalance.
        dailyCreditAmount[_getCurrentDay()] += totalPrincipalTokenAmountToCredit;
        creditDebitBalance += int256(totalPrincipalTokenAmountToCredit);

        /// @dev Calculate the fees amount.
        uint256 feeAmount = totalPrincipalTokenAmountToCredit.percentMul(feesRate);
        uint256 principalTokenAmountCredited = totalPrincipalTokenAmountToCredit - feeAmount;

        emit EventsLib.OFTSwapped(
            msg.sender,
            _to,
            totalPrincipalTokenAmountToCredit,
            principalTokenAmountCredited,
            feeAmount
        );

        /// @dev if the fees amount is greater than 0, mint the fees to the feesRecipient.
        if (feeAmount > 0) {
            _creditPrincipalToken(feesRecipient, feeAmount);
        }
        /// @dev Mint the principalToken to the user.
        _creditPrincipalToken(_to, principalTokenAmountCredited);

        return principalTokenAmountCredited;
    }

    //-------------------------------------------
    // External view functions
    //-------------------------------------------

    /// @notice The principalToken address.
    function getPrincipalToken() external view returns (address) {
        return address(principalToken);
    }

    /// @notice The credit daily limit for the token.
    function getDailyCreditLimit() external view returns (uint256) {
        return dailyCreditLimit;
    }

    /// @notice The debit daily limit for the token.
    function getDailyDebitLimit() external view returns (uint256) {
        return dailyDebitLimit;
    }

    /// @notice The global credit limit for the token.
    function getGlobalCreditLimit() external view returns (uint256) {
        return globalCreditLimit;
    }

    /// @notice The global debit limit for the token.
    function getGlobalDebitLimit() external view returns (uint256) {
        return uint256(MathLib.abs(globalDebitLimit));
    }

    /// @notice Whether the `isIsolateMode` is enabled.
    function getIsIsolateMode() external view returns (bool) {
        return isIsolateMode;
    }

    /// @notice Retrieves the amount of principalToken bridged.
    /// @dev If amount < 0, it means that more tokens were credit than debit.
    function getCreditDebitBalance() external view returns (int256) {
        return creditDebitBalance;
    }

    /// @notice The fees recipient address.
    /// @dev The recipient receives the principalToken fees.
    function getFeesRecipient() external view returns (address) {
        return feesRecipient;
    }

    /// @notice The fees rate in basic point.
    function getFeesRate() external view returns (uint16) {
        return feesRate;
    }

    /// @notice Retrieves the current daily credit amount of PrincipalToken.
    function getCurrentDailyCreditAmount() external view returns (uint256) {
        return dailyCreditAmount[_getCurrentDay()];
    }

    /// @notice Retrieves the current daily debit amount of PrincipalToken.
    function getCurrentDailyDebitAmount() external view returns (uint256) {
        return dailyDebitAmount[_getCurrentDay()];
    }

    /// @notice Retrieves the MAX amount of PrincipalToken to be credit regarding limits.
    function getMaxCreditableAmount() external view returns (uint256) {
        if (creditDebitBalance >= int256(globalCreditLimit)) return 0;
        uint256 globalMax = uint256(int256(globalCreditLimit) - creditDebitBalance);
        uint256 currentCreditAmount = dailyCreditAmount[_getCurrentDay()];
        uint256 dailyMax = dailyCreditLimit > currentCreditAmount 
            ? dailyCreditLimit - currentCreditAmount
            : 0;
        return MathLib.min(globalMax, dailyMax);
    }

    /// @notice Retrieves the MAX amount of PrincipalToken to be debit regarding limits.
    function getMaxDebitableAmount() external view returns (uint256) {
        if (isIsolateMode && creditDebitBalance <= 0) return 0;
        if (creditDebitBalance <= globalDebitLimit) return 0;
        uint256 globalMax = MathLib.abs(globalDebitLimit - creditDebitBalance);
        uint256 currentDebitAmount = dailyDebitAmount[_getCurrentDay()];
        uint256 dailyMax = dailyDebitLimit > currentDebitAmount
            ? dailyDebitLimit - currentDebitAmount
            : 0;
        uint256 result = MathLib.min(globalMax, dailyMax);
        if (isIsolateMode) return MathLib.min(result, uint256(creditDebitBalance));
        return result;
    }

    //-------------------------------------------
    // OnlyOwner functions
    //-------------------------------------------

    /// @notice Allow owner to rescue any locked tokens in the contract in case of an emergency.
    /// @param _token The token address to withdraw
    /// @param _to The address to transfer the tokens to
    /// @param _amount The amount of tokens to withdraw.
    function emergencyRescue(address _token, address _to, uint256 _amount) external onlyOwner whenPaused {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Toggle `isIsolateMode` to enable/disable the isolation mode.
    function toggleIsolateMode() external onlyOwner {
        _setIsolateMode(!isIsolateMode);
    }

    /// @notice Sets `_newFeesRate` as `feesRate` of the fees applied on principalToken credit.
    /// @dev The fees rate in basic point with a maximum of 10% (10_00 in bp)
    /// @param _newFeesRate The new fees rate in basic point.
    function setFeesRate(uint16 _newFeesRate) external onlyOwner {
        _setFeesRate(_newFeesRate);
    }

    /// @notice Sets `_dailyCreditLimit` as `dailyCreditLimit` of daily amount of principalToken to be credit.
    /// @param _dailyCreditLimit The daily limit of principalToken to be credit.
    function setDailyCreditLimit(uint256 _dailyCreditLimit) external onlyOwner {
        _setDailyCreditLimit(_dailyCreditLimit);
    }

    /// @notice Sets `_globalCreditLimit` as `globalCreditLimit` of max amount of principalToken to be credit.
    /// @param _globalCreditLimit The max limit of principalToken to be credit.
    function setGlobalCreditLimit(uint256 _globalCreditLimit) external onlyOwner {
        _setGlobalCreditLimit(_globalCreditLimit);
    }

    /// @notice Sets `_dailyDebitLimit` as `dailyDebitLimit` of daily amount of principalToken to be debit.
    /// @param _dailyDebitLimit The daily limit of principalToken to be debit.
    function setDailyDebitLimit(uint256 _dailyDebitLimit) external onlyOwner {
        _setDailyDebitLimit(_dailyDebitLimit);
    }

    /// @notice Sets `_globalDebitLimit` as `globalDebitLimit` of max amount of principalToken to be debit.
    /// @param _globalDebitLimit The max limit of principalToken to be debit.
    function setGlobalDebitLimit(uint256 _globalDebitLimit) external onlyOwner {
        _setGlobalDebitLimit(_globalDebitLimit);
    }

    /// @notice Sets `_newFeesRecipient` as `feesRecipient` of the fees.
    /// @param _newFeesRecipient The new fees recipient address.
    function setFeesRecipient(address _newFeesRecipient) external onlyOwner {
        _setFeesRecipient(_newFeesRecipient);
    }

    /// @notice Allow owner to pause the contract
    /// @dev This function can only be called by the owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Allow owner to unpause the contract
    /// @dev This function can only be called by the owner
    function unpause() external onlyOwner {
        _unpause();
    }

    //-------------------------------------------
    // Internal functions
    //-------------------------------------------

    /// @dev Internal function to handle the receive on the LayerZero endpoint.
    /// @param _origin The origin information.
    ///  - srcEid: The source chain endpoint ID.
    ///  - sender: The sender address from the src chain.
    ///  - nonce: The nonce of the LayerZero message.
    /// @param _guid The unique identifier for the received LayerZero message.
    /// @param _message The encoded message.
    /// @dev _executor The address of the executor.
    /// @dev _extraData Additional data.
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address /*_executor*/, // @dev unused in the default implementation.
        bytes calldata /*_extraData*/ // @dev unused in the default implementation.
    ) internal virtual override nonReentrant {
        // @dev The src sending chain doesnt know the address length on this chain (potentially non-evm)
        // Thus everything is bytes32() encoded in flight.
        address to = _message.sendTo().bytes32ToAddress();

        /// @dev Extract from message if the tokens burned from the original chain
        /// was the principalToken or the OFT token. If true, fees could be applied.
        (, bool feeApplicable) = abi.decode(_message.composeMsg(), (bytes32, bool));

        // @dev Credit the amount to the recipient and return the ACTUAL amount the recipient received in local
        // decimals
        (uint256 amountReceived, uint256 oftReceived, uint256 feesAmount) = _credit(
            to,
            _toLD(_message.amountSD()),
            _origin.srcEid,
            feeApplicable
        );

        emit EventsLib.BridgeableTokenReceived(
            _guid,
            _origin.srcEid,
            _origin.sender.bytes32ToAddress(),
            to,
            amountReceived,
            oftReceived,
            feesAmount
        );
    }

    //-------------------------------------------
    // Private functions
    //-------------------------------------------

    /// @dev Excute the send operation for both send and sendWithPermit
    /// @param _sendParam The parameters for the send operation.
    /// @param _fee The calculated fees for the send() operation.
    ///      - nativeFee: The native fees.
    ///      - lzTokenFee: The lzToken fees.
    /// @param _refundAddress The address to receive any excess funds.
    /// @return msgReceipt The receipt for the send operation.
    /// @return oftReceipt The OFT receipt information.
    ///
    /// @dev MessagingReceipt: LayerZero msg receipt
    ///  - guid: The unique identifier for the sent message.
    ///  - nonce: The nonce of the sent message.
    ///  - fees: The LayerZero fees incurred for the message.
    function _send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) private returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        if (_sendParam.composeMsg.length != 32) revert ErrorsLib.InvalidMsgLength();
        address to = _sendParam.to.bytes32ToAddress();
        if (to == address(0)) revert CommonErrorsLib.AddressZero();
        
        bool isPrincipalTokenSent = abi.decode(_sendParam.composeMsg, (bool));

        (uint256 amountSent, uint256 amountReceived) = _debit(
            isPrincipalTokenSent,
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );

        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceived);
        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSent, amountReceived);

        emit EventsLib.BridgeableTokenSent(
            msgReceipt.guid,
            _sendParam.dstEid,
            msg.sender,
            _sendParam.to.bytes32ToAddress(),
            _fee.nativeFee,
            isPrincipalTokenSent,
            amountSent,
            amountReceived
        );
    }

    /// @dev Burns tokens from the sender's specified balance.
    /// @param _isPrincipalTokenToSend the flag to send the principalToken or the OFT token from the caller.
    /// @param _amountLD The amount of tokens to send in local decimals.
    /// @param _minAmountLD The minimum amount to send in local decimals.
    /// @param _dstEid The destination chain ID.
    /// @return amountSentLD The amount sent in local decimals.
    /// @return amountReceivedLD The amount received on the remote in local decimals.
    function _debit(
        bool _isPrincipalTokenToSend,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) private returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        if (_isPrincipalTokenToSend) {
            /// @dev Assert that the amount to send DO NOT exceed the daily limit.
            uint256 day = _getCurrentDay();
            if (dailyDebitAmount[day] + amountSentLD > dailyDebitLimit) {
                revert ErrorsLib.DailyDebitLimitReached();
            }

            /// @dev Update the daily usage and the creditDebitBalance.
            dailyDebitAmount[day] += amountSentLD;
            creditDebitBalance -= int256(amountSentLD);

            if (isIsolateMode) {
                /// @dev Assert that the final creditDebitBalance is greater or equal than 0.
                if (creditDebitBalance < 0) revert ErrorsLib.IsolateModeLimitReach();
            }

            /// @dev Assert that the final creditDebitBalance is greater or equal than the globalDebitLimit.
            if (creditDebitBalance < globalDebitLimit) revert ErrorsLib.GlobalDebitLimitReached();

            ITokenP(address(principalToken)).burnFrom( amountSentLD, msg.sender, address(this));

            emit EventsLib.PrincipalTokenDebited(msg.sender, amountSentLD);
        } else {
            _burn(msg.sender, amountSentLD);
        }
    }

    /// @notice Credits tokens to the specified address.
    /// @param _to The address to credit the tokens to.
    /// @param _amountLD The amount of tokens to credit in local decimals.
    /// @dev _srcEid The source chain ID.
    /// @param _isFeeApplicable The flag to apply fees or not.
    /// @return amountReceived The amount of tokens ACTUALLY received in local decimals.
    /// @return oftReceived The amount of OFT tokens received in local decimals.
    /// @return feeAmount The amount of fees token minted in local decimals.
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32, //_srcEid,
        bool _isFeeApplicable
    ) private returns (uint256 amountReceived, uint256 oftReceived, uint256 feeAmount) {
        (amountReceived, feeAmount) = _handleCreditPrincipalToken(_to, _amountLD, _isFeeApplicable);

        oftReceived = _amountLD - amountReceived - feeAmount;
        /// If OftReceived > 0 we must be credit to the user OFT tokens to match the total amount he must be credited.
        if (oftReceived > 0) {
            _mint(_to, oftReceived);
        }
    }

    /// @notice Calculates and credit principal tokens to `_to` address and the `feesRecipient`.
    /// @param _to The address to credit the tokens to.
    /// @param _amountLD The amount of token expected to be credited in local decimals.
    /// @param _isFeeApplicable The flag to apply fees or not
    /// @return amountReceived The amount of principal token received in local decimals.
    /// @return feeAmount The amount of fees token minted in local decimals.
    function _handleCreditPrincipalToken(
        address _to,
        uint256 _amountLD,
        bool _isFeeApplicable
    ) private returns (uint256 amountReceived, uint256 feeAmount) {
        amountReceived = _calculatePrincipalTokenAmountToCredit(_amountLD);

        if (amountReceived > 0) {
            dailyCreditAmount[_getCurrentDay()] += amountReceived;
            creditDebitBalance += int256(amountReceived);
            if (_isFeeApplicable) {
                if (feesRate > 0) {
                    feeAmount = amountReceived.percentMul(feesRate);
                    amountReceived -= feeAmount;
                    _creditPrincipalToken(feesRecipient, feeAmount);
                }
            }
            _creditPrincipalToken(_to, amountReceived);
        }
    }

    /// @notice Credits principal tokens (mint) to `_to` address.
    /// @param _to The address to credit the tokens to.
    /// @param _amount The amount of tokens to credit.
    function _creditPrincipalToken(
        address _to,
        uint256 _amount
    ) private {
        emit EventsLib.PrincipalTokenCredited(_to, _amount);
        ITokenP(address(principalToken)).mint(_to, _amount);
    }

    /// @notice Calculates the amount of principalToken that can be credit regarding the limits.
    /// @param _amount The amount of token expected to be credit.
    /// @return principalTokenAmountToCredit The total amount of principalToken to credit.
    function _calculatePrincipalTokenAmountToCredit(
        uint256 _amount
    ) private view returns (uint256 principalTokenAmountToCredit) {
        if (creditDebitBalance >= int256(globalCreditLimit)) return 0;
        principalTokenAmountToCredit = SafeCast.toInt256(_amount) + creditDebitBalance > int256(globalCreditLimit)
            ? uint256(int256(globalCreditLimit) - creditDebitBalance)
            : _amount;
        uint256 dailyUsage = dailyCreditAmount[_getCurrentDay()];
        if (dailyUsage + principalTokenAmountToCredit > dailyCreditLimit) {
            principalTokenAmountToCredit = dailyCreditLimit > dailyUsage ? dailyCreditLimit - dailyUsage : 0;
        }
    }

    /// @notice Retrieves the current day.
    /// @return The current day.
    function _getCurrentDay() private view returns (uint256) {
        return block.timestamp / DAY_IN_SECONDS;
    }

    /// @notice Sets the `isIsolateMode` flag.
    /// @param _isIsolateMode The new value for the `isIsolateMode` flag.
    function _setIsolateMode(bool _isIsolateMode) private {
        isIsolateMode = _isIsolateMode;
        emit EventsLib.IsolateModeToggled(_isIsolateMode);
    }

    /// @notice Sets `_newDailyCreditLimit` as `dailyCreditLimit` of daily amount of principalToken that can be
    /// credit.
    /// @param _newDailyCreditLimit The daily limit of principalToken that can be credit.
    function _setDailyCreditLimit(uint256 _newDailyCreditLimit) private {
        dailyCreditLimit = _newDailyCreditLimit;
        emit EventsLib.DailyCreditLimitSet(_newDailyCreditLimit);
    }

    /// @notice Sets `_newGlobalCreditLimit` as `globalCreditLimit` of max amount of principalToken that can be
    /// credit.
    /// @param _newGlobalCreditLimit The max limit of principalToken that can be credit.
    function _setGlobalCreditLimit(uint256 _newGlobalCreditLimit) private {
        if (_newGlobalCreditLimit > MAX_GLOBAL_LIMIT) {
            revert ErrorsLib.GlobalLimitOverFlow();
        }
        globalCreditLimit = _newGlobalCreditLimit;
        emit EventsLib.GlobalCreditLimitSet(_newGlobalCreditLimit);
    }

    /// @notice Sets `_newDailyDebitLimit` as `dailyDebitLimit` of daily amount of principalToken that can be
    /// debit.
    /// @param _newDailyDebitLimit The daily limit of principalToken that can be debit.
    function _setDailyDebitLimit(uint256 _newDailyDebitLimit) private {
        dailyDebitLimit = _newDailyDebitLimit;
        emit EventsLib.DailyDebitLimitSet(_newDailyDebitLimit);
    }

    /// @notice Sets `_newGlobalDebitLimit` as `globalDebitLimit` of max amount of principalToken that can be
    /// debit.
    /// @param _newGlobalDebitLimit The max limit of principalToken that can be debit.
    function _setGlobalDebitLimit(uint256 _newGlobalDebitLimit) private {
        if (_newGlobalDebitLimit > MAX_GLOBAL_LIMIT) {
            revert ErrorsLib.GlobalLimitOverFlow();
        }
        globalDebitLimit = MathLib.neg(_newGlobalDebitLimit);
        emit EventsLib.GlobalDebitLimitSet(_newGlobalDebitLimit);
    }

    /// @notice Sets `_newFeesRate` as `feesRate` of the fees applied on principalToken to be credit.
    /// @param _newFeesRate The new fees rate in basic point.
    function _setFeesRate(uint16 _newFeesRate) private {
        if (_newFeesRate > MAX_FEE) revert ErrorsLib.MaxFeesRateExceeded();
        feesRate = _newFeesRate;
        emit EventsLib.FeesRateSet(_newFeesRate);
    }

    /// @dev Sets `_newFeesRecipient` as `feesRecipient` of the fees.
    /// @param _newFeesRecipient The new fees recipient address.
    function _setFeesRecipient(address _newFeesRecipient) private {
        if (_newFeesRecipient == address(0)) revert CommonErrorsLib.AddressZero();
        feesRecipient = _newFeesRecipient;
        emit EventsLib.FeesRecipientSet(_newFeesRecipient);
    }
}
