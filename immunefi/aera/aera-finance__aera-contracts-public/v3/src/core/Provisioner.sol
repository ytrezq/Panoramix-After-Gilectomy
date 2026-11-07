// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@oz/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuardTransient } from "@oz/utils/ReentrancyGuardTransient.sol";

import { Math } from "@oz/utils/math/Math.sol";
import { BitMaps } from "@oz/utils/structs/BitMaps.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { Auth2Step } from "src/core/Auth2Step.sol";

import {
    AUTO_PRICE_FIXED_PRICE_FLAG,
    DEPOSIT_REDEEM_FLAG,
    MAX_DEPOSIT_REFUND_TIMEOUT,
    MAX_SECONDS_TO_DEADLINE,
    MIN_DEPOSIT_MULTIPLIER,
    MIN_REDEEM_MULTIPLIER,
    ONE_IN_BPS,
    ONE_UNIT
} from "src/core/Constants.sol";
import { Request, RequestType, TokenDetails } from "src/core/Types.sol";
import { IMultiDepositorVault } from "src/core/interfaces/IMultiDepositorVault.sol";
import { IPriceAndFeeCalculator } from "src/core/interfaces/IPriceAndFeeCalculator.sol";
import { IProvisioner } from "src/core/interfaces/IProvisioner.sol";

/// @title Provisioner
/// @notice Entry and exit point for {MultiDepositorVault}. Handles all deposits and redemptions
/// Uses {IPriceAndFeeCalculator} to convert between tokens and vault units. Supports both sync and async deposits; only
/// async redeems. Manages deposit caps, refund timeouts, and request replay protection. All assets must flow through
/// this contract to enter or exit the vault. Sync deposits are processed instantly, but stay refundable for a period of
/// time. Async requests can either be solved by authorized solvers, going through the vault, or directly by anyone
/// willing to pay units (for deposits) or tokens (for redeems), pocketing the solver tip, always paid in tokens
contract Provisioner is IProvisioner, Auth2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using BitMaps for BitMaps.BitMap;

    ////////////////////////////////////////////////////////////
    //                         Immutables                     //
    ////////////////////////////////////////////////////////////

    /// @notice The price and fee calculator contract
    IPriceAndFeeCalculator public immutable PRICE_FEE_CALCULATOR;

    /// @notice The multi depositor vault contract
    address public immutable MULTI_DEPOSITOR_VAULT;

    ////////////////////////////////////////////////////////////
    //                         Storage                        //
    ////////////////////////////////////////////////////////////

    /// @notice Mapping of token to token details
    mapping(IERC20 token => TokenDetails details) public tokensDetails;

    /// @notice Maximum total value of deposits in numeraire terms
    uint256 public depositCap;

    /// @notice Time period in seconds during which sync deposits can be refunded
    uint256 public depositRefundTimeout;

    /// @notice Mapping of active sync deposit hashes
    /// @dev True if a sync deposit is active with the hashed parameters
    mapping(bytes32 syncDepositHash => bool exists) public syncDepositHashes;

    /// @notice Mapping of async deposit hash to its existence
    /// @dev True if deposit request exists, false if it was refunded or solved
    mapping(bytes32 asyncDepositHash => bool exists) public asyncDepositHashes;

    /// @notice Mapping of async redeem hash to its existence
    /// @dev True if redeem request exists, false if it was refunded or solved
    mapping(bytes32 asyncRedeemHash => bool exists) public asyncRedeemHashes;

    /// @notice Mapping of user address to timestamp until which their units are locked
    mapping(address user => uint256 unitsLockedUntil) public userUnitsRefundableUntil;

    ////////////////////////////////////////////////////////////
    //                       Modifiers                        //
    ////////////////////////////////////////////////////////////

    /// @notice Ensures the caller is not the vault
    modifier anyoneButVault() {
        // Requirements: check that the caller is not the vault
        require(msg.sender != MULTI_DEPOSITOR_VAULT, Aera__CallerIsVault());
        _;
    }

    constructor(
        IPriceAndFeeCalculator priceAndFeeCalculator,
        address multiDepositorVault,
        address owner_,
        Authority authority_
    ) Auth2Step(owner_, authority_) {
        // Requirements: immutables are not zero addresses
        require(address(priceAndFeeCalculator) != address(0), Aera__ZeroAddressPriceAndFeeCalculator());
        require(multiDepositorVault != address(0), Aera__ZeroAddressMultiDepositorVault());

        // Effects: set immutables
        PRICE_FEE_CALCULATOR = priceAndFeeCalculator;
        MULTI_DEPOSITOR_VAULT = multiDepositorVault;
    }

    ////////////////////////////////////////////////////////////
    //              Public / External Functions               //
    ////////////////////////////////////////////////////////////

    /// @inheritdoc IProvisioner
    function deposit(IERC20 token, uint256 tokensIn, uint256 minUnitsOut)
        external
        anyoneButVault
        returns (uint256 unitsOut)
    {
        // Requirements: token amount and min units out are positive
        require(tokensIn != 0, Aera__TokensInZero());
        require(minUnitsOut != 0, Aera__MinUnitsOutZero());

        // Requirements: sync deposits are enabled
        TokenDetails storage tokenDetails = _requireSyncDepositsEnabled(token);

        // Interactions: convert token amount to units out
        unitsOut = _tokensToUnitsFloorIfActive(token, tokensIn, tokenDetails.depositMultiplier);
        // Requirements: units out meets min units out
        require(unitsOut >= minUnitsOut, Aera__MinUnitsOutNotMet());
        // Requirements + interactions: convert new total units to numeraire and check against deposit cap
        _requireDepositCapNotExceeded(unitsOut);

        // Effects + interactions: sync deposit
        _syncDeposit(token, tokensIn, unitsOut);
    }

    /// @inheritdoc IProvisioner
    function mint(IERC20 token, uint256 unitsOut, uint256 maxTokensIn)
        external
        anyoneButVault
        returns (uint256 tokensIn)
    {
        // Requirements: tokens and units amount are positive
        require(unitsOut != 0, Aera__UnitsOutZero());
        require(maxTokensIn != 0, Aera__MaxTokensInZero());

        // Requirements: sync deposits are enabled
        TokenDetails storage tokenDetails = _requireSyncDepositsEnabled(token);

        // Requirements + interactions: convert new total units to numeraire and check against deposit cap
        _requireDepositCapNotExceeded(unitsOut);
        // Interactions: convert units to tokens
        tokensIn = _unitsToTokensCeilIfActive(token, unitsOut, tokenDetails.depositMultiplier);
        // Requirements: token in is less than or equal to max tokens in
        require(tokensIn <= maxTokensIn, Aera__MaxTokensInExceeded());

        // Effects + interactions: sync deposit
        _syncDeposit(token, tokensIn, unitsOut);
    }

    /// @inheritdoc IProvisioner
    function refundDeposit(
        address sender,
        IERC20 token,
        uint256 tokenAmount,
        uint256 unitsAmount,
        uint256 refundableUntil
    ) external requiresAuth {
        // Requirements: refundable timestamp is in the future
        require(refundableUntil >= block.timestamp, Aera__RefundPeriodExpired());

        bytes32 depositHash = _getDepositHash(sender, token, tokenAmount, unitsAmount, refundableUntil);
        // Requirements: hash has been set
        require(syncDepositHashes[depositHash], Aera__DepositHashNotFound());
        // Effects: unset hash as used
        syncDepositHashes[depositHash] = false;

        // Interactions: exit vault
        IMultiDepositorVault(MULTI_DEPOSITOR_VAULT).exit(sender, token, tokenAmount, unitsAmount, sender);

        // Log emit deposit refunded event
        emit DirectDepositRefunded(depositHash);
    }

    /// @inheritdoc IProvisioner
    function requestDeposit(
        IERC20 token,
        uint256 tokensIn,
        uint256 minUnitsOut,
        uint256 solverTip,
        uint256 deadline,
        uint256 maxPriceAge,
        bool isFixedPrice
    ) external anyoneButVault {
        // Requirements: token amount and min units out are positive, deadline is in the future, deadline is not too far
        // in the future, async deposits are enabled, vault is not paused in the PriceAndFeeCalculator
        require(tokensIn != 0, Aera__TokensInZero());
        require(minUnitsOut != 0, Aera__MinUnitsOutZero());
        require(deadline > block.timestamp, Aera__DeadlineInPast());
        unchecked {
            require(deadline - block.timestamp <= MAX_SECONDS_TO_DEADLINE, Aera__DeadlineTooFarInFuture());
        }
        require(tokensDetails[token].asyncDepositEnabled, Aera__AsyncDepositDisabled());
        require(!PRICE_FEE_CALCULATOR.isVaultPaused(MULTI_DEPOSITOR_VAULT), Aera__PriceAndFeeCalculatorVaultPaused());
        require(solverTip == 0 || !isFixedPrice, Aera__FixedPriceSolverTipNotAllowed());

        // Interactions: transfer tokens from sender to provisioner
        token.safeTransferFrom(msg.sender, address(this), tokensIn);

        RequestType requestType = isFixedPrice ? RequestType.DEPOSIT_FIXED_PRICE : RequestType.DEPOSIT_AUTO_PRICE;

        bytes32 depositHash = _getRequestHashParams(
            token, msg.sender, requestType, tokensIn, minUnitsOut, solverTip, deadline, maxPriceAge
        );
        // Requirements: hash has not been used
        require(!asyncDepositHashes[depositHash], Aera__HashCollision());
        // Effects: set hash as used
        asyncDepositHashes[depositHash] = true;

        // Log emit deposit requested event
        emit DepositRequested(
            msg.sender, token, tokensIn, minUnitsOut, solverTip, deadline, maxPriceAge, isFixedPrice, depositHash
        );
    }

    /// @inheritdoc IProvisioner
    function requestRedeem(
        IERC20 token,
        uint256 unitsIn,
        uint256 minTokensOut,
        uint256 solverTip,
        uint256 deadline,
        uint256 maxPriceAge,
        bool isFixedPrice
    ) external anyoneButVault {
        // Requirements: units amount is positive, min token out is positive, deadline is in the future, deadline is not
        // too far in the future, async withdrawals are enabled, vault is not paused in the PriceAndFeeCalculator
        require(unitsIn != 0, Aera__UnitsInZero());
        require(minTokensOut != 0, Aera__MinTokenOutZero());
        require(deadline > block.timestamp, Aera__DeadlineInPast());
        unchecked {
            require(deadline - block.timestamp <= MAX_SECONDS_TO_DEADLINE, Aera__DeadlineTooFarInFuture());
        }
        require(tokensDetails[token].asyncRedeemEnabled, Aera__AsyncRedeemDisabled());
        require(!PRICE_FEE_CALCULATOR.isVaultPaused(MULTI_DEPOSITOR_VAULT), Aera__PriceAndFeeCalculatorVaultPaused());
        require(solverTip == 0 || !isFixedPrice, Aera__FixedPriceSolverTipNotAllowed());

        // Interactions: transfer units from sender to provisioner
        IERC20(MULTI_DEPOSITOR_VAULT).safeTransferFrom(msg.sender, address(this), unitsIn);

        RequestType requestType = isFixedPrice ? RequestType.REDEEM_FIXED_PRICE : RequestType.REDEEM_AUTO_PRICE;

        bytes32 redeemHash = _getRequestHashParams(
            token, msg.sender, requestType, minTokensOut, unitsIn, solverTip, deadline, maxPriceAge
        );
        // Requirements: hash has not been used
        require(!asyncRedeemHashes[redeemHash], Aera__HashCollision());
        // Effects: set hash as used
        asyncRedeemHashes[redeemHash] = true;

        // Log emit redeem requested event
        emit RedeemRequested(
            msg.sender, token, minTokensOut, unitsIn, solverTip, deadline, maxPriceAge, isFixedPrice, redeemHash
        );
    }

    /// @inheritdoc IProvisioner
    function refundRequest(IERC20 token, Request calldata request) external nonReentrant {
        // Requirements: deadline is in the past or authorized
        require(
            request.deadline < block.timestamp || isAuthorized(msg.sender, msg.sig),
            Aera__DeadlineInFutureAndUnauthorized()
        );

        bytes32 requestHash = _getRequestHash(token, request);

        if (_isRequestTypeDeposit(request.requestType)) {
            // Requirements: hash has been set
            require(asyncDepositHashes[requestHash], Aera__HashNotFound());
            // Effects: unset hash as used
            asyncDepositHashes[requestHash] = false;
            // Interactions: transfer tokens from provisioner to sender
            token.safeTransfer(request.user, request.tokens);
            // Log emit deposit refunded event
            emit DepositRefunded(requestHash);
        } else {
            // Requirements: hash has been set
            require(asyncRedeemHashes[requestHash], Aera__HashNotFound());
            // Effects: unset hash as used
            asyncRedeemHashes[requestHash] = false;
            // Interactions: transfer units from provisioner to sender
            IERC20(MULTI_DEPOSITOR_VAULT).safeTransfer(request.user, request.units);
            // Log emit redeem refunded event
            emit RedeemRefunded(requestHash);
        }
    }

    // solhint-disable code-complexity
    /// @inheritdoc IProvisioner
    function solveRequestsVault(IERC20 token, Request[] calldata requests) external requiresAuth nonReentrant {
        // Interactions: get price age
        uint256 priceAge = PRICE_FEE_CALCULATOR.getVaultsPriceAge(MULTI_DEPOSITOR_VAULT);

        uint256 solverTip;
        Request calldata request;

        uint256 length = requests.length;
        TokenDetails memory tokenDetails = tokensDetails[token];
        bool depositsExist;
        for (uint256 i = 0; i < length; i++) {
            request = requests[i];
            if (_isRequestTypeDeposit(request.requestType)) {
                // Requirements: async deposit is enabled
                if (!tokenDetails.asyncDepositEnabled) {
                    // Log emit async deposit disabled event
                    emit AsyncDepositDisabled(i);
                    continue;
                }

                if (!depositsExist) {
                    depositsExist = true;
                    token.forceApprove(MULTI_DEPOSITOR_VAULT, type(uint256).max);
                }

                if (_isRequestTypeAutoPrice(request.requestType)) {
                    // Requirements + Effects + Interactions: solve auto price deposit
                    solverTip +=
                        _solveDepositVaultAutoPrice(token, tokenDetails.depositMultiplier, request, priceAge, i);
                } else {
                    // Requirements + Effects + Interactions: solve fixed price deposit
                    solverTip +=
                        _solveDepositVaultFixedPrice(token, tokenDetails.depositMultiplier, request, priceAge, i);
                }
            } else {
                // Requirements: async redeem is enabled
                if (!tokenDetails.asyncRedeemEnabled) {
                    // Log emit async redeem disabled event
                    emit AsyncRedeemDisabled(i);
                    continue;
                }

                if (_isRequestTypeAutoPrice(request.requestType)) {
                    // Requirements + Effects + Interactions: solve auto price redeem
                    solverTip += _solveRedeemVaultAutoPrice(token, tokenDetails.redeemMultiplier, request, priceAge, i);
                } else {
                    // Requirements + Effects + Interactions: solve fixed price redeem
                    solverTip += _solveRedeemVaultFixedPrice(token, tokenDetails.redeemMultiplier, request, priceAge, i);
                }
            }
        }

        if (solverTip != 0) {
            // Interactions: transfer solver tip from provisioner to sender
            token.safeTransfer(msg.sender, solverTip);
        }

        if (depositsExist) {
            // Interactions: set approval to 0
            token.forceApprove(MULTI_DEPOSITOR_VAULT, 0);
        }
    }

    /// @inheritdoc IProvisioner
    function solveRequestsDirect(IERC20 token, Request[] calldata requests) external nonReentrant {
        // Requirements: vault is not paused in the priceAndFeeCalculator
        require(!PRICE_FEE_CALCULATOR.isVaultPaused(MULTI_DEPOSITOR_VAULT), Aera__PriceAndFeeCalculatorVaultPaused());

        uint256 length = requests.length;
        TokenDetails storage tokenDetails = tokensDetails[token];
        for (uint256 i = 0; i < length; i++) {
            if (_isRequestTypeDeposit(requests[i].requestType)) {
                // Requirements: async deposit is enabled
                require(tokenDetails.asyncDepositEnabled, Aera__AsyncDepositDisabled());
                // Requirements: direct deposits can only solve fixed price requests
                require(!_isRequestTypeAutoPrice(requests[i].requestType), Aera__AutoPriceSolveNotAllowed());
                // Requirements + Effects + Interactions: solve direct deposit
                _solveDepositDirect(token, requests[i]);
            } else {
                // Requirements: async redeem is enabled
                require(tokenDetails.asyncRedeemEnabled, Aera__AsyncRedeemDisabled());
                // Requirements: direct redeems can only solve fixed price requests
                require(!_isRequestTypeAutoPrice(requests[i].requestType), Aera__AutoPriceSolveNotAllowed());
                // Requirements + Effects + Interactions: solve direct redeem
                _solveRedeemDirect(token, requests[i]);
            }
        }
    }

    /// @inheritdoc IProvisioner
    function setDepositDetails(uint256 depositCap_, uint256 depositRefundTimeout_) external requiresAuth {
        // Requirements: deposit cap is not zero
        require(depositCap_ != 0, Aera__DepositCapZero());
        // Requirements: deposit refund timeout does not exceed the safety cap
        require(depositRefundTimeout_ <= MAX_DEPOSIT_REFUND_TIMEOUT, Aera__MaxDepositRefundTimeoutExceeded());

        // Effects: set deposit cap and refund timeout
        depositCap = depositCap_;
        depositRefundTimeout = depositRefundTimeout_;

        // Log emit deposit details updated event
        emit DepositDetailsUpdated(depositCap_, depositRefundTimeout_);
    }

    /// @inheritdoc IProvisioner
    function setTokenDetails(IERC20 token, TokenDetails calldata details) external requiresAuth {
        // Requirements: check that the token is not the vault’s own unit token
        require(address(token) != MULTI_DEPOSITOR_VAULT, Aera__InvalidToken());

        uint256 depositMultiplier = details.depositMultiplier;
        // Requirements: deposit multiplier is greater than or equal to min deposit multiplier
        require(depositMultiplier >= MIN_DEPOSIT_MULTIPLIER, Aera__DepositMultiplierTooLow());
        require(depositMultiplier <= ONE_IN_BPS, Aera__DepositMultiplierTooHigh());
        uint256 redeemMultiplier = details.redeemMultiplier;
        // Requirements: redeem multiplier is greater than or equal to min redeem multiplier
        require(redeemMultiplier >= MIN_REDEEM_MULTIPLIER, Aera__RedeemMultiplierTooLow());
        // Requirements: redeem multiplier is less than or equal to one in BPS
        require(redeemMultiplier <= ONE_IN_BPS, Aera__RedeemMultiplierTooHigh());

        // Effects: set token details
        tokensDetails[token] = details;

        if (details.asyncRedeemEnabled || details.asyncDepositEnabled || details.syncDepositEnabled) {
            // Requirements: check that the token can be priced
            // convertUnitsToToken instead of convertTokensToUnits to avoid having to call token.decimals()
            require(
                PRICE_FEE_CALCULATOR.convertUnitsToToken(MULTI_DEPOSITOR_VAULT, token, ONE_UNIT) != 0,
                Aera__TokenCantBePriced()
            );
        }

        // Log emit token details set event
        emit TokenDetailsSet(token, details);
    }

    /// @inheritdoc IProvisioner
    function removeToken(IERC20 token) external requiresAuth {
        // Effects: remove tokensDetails
        delete tokensDetails[token];

        // Log emit token removed event
        emit TokenRemoved(token);
    }

    /// @inheritdoc IProvisioner
    function maxDeposit() external view returns (uint256) {
        // Interactions: get current total supply
        uint256 totalSupply = IERC20(MULTI_DEPOSITOR_VAULT).totalSupply();
        // Interactions: convert total supply to numeraire
        uint256 totalAssets = PRICE_FEE_CALCULATOR.convertUnitsToNumeraire(MULTI_DEPOSITOR_VAULT, totalSupply);

        // Return max of 0 or difference between deposit cap and total assets
        return totalAssets < depositCap ? depositCap - totalAssets : 0;
    }

    /// @inheritdoc IProvisioner
    function areUserUnitsLocked(address user) external view returns (bool) {
        return userUnitsRefundableUntil[user] >= block.timestamp;
    }

    /// @inheritdoc IProvisioner
    function getDepositHash(
        address user,
        IERC20 token,
        uint256 tokenAmount,
        uint256 unitsAmount,
        uint256 refundableUntil
    ) external pure returns (bytes32) {
        return _getDepositHash(user, token, tokenAmount, unitsAmount, refundableUntil);
    }

    /// @inheritdoc IProvisioner
    function getRequestHash(IERC20 token, Request calldata request) external pure returns (bytes32) {
        return _getRequestHash(token, request);
    }

    ////////////////////////////////////////////////////////////
    //              Internal / Private Functions              //
    ////////////////////////////////////////////////////////////

    /// @notice Handles a synchronous deposit, records the deposit hash, and enters the vault
    /// @dev Reverts if the deposit hash already exists. Sets the refundable period for the user
    /// @param token The ERC20 token to deposit
    /// @param tokenAmount The amount of tokens to deposit
    /// @param unitAmount The amount of vault units to mint for the user
    function _syncDeposit(IERC20 token, uint256 tokenAmount, uint256 unitAmount) internal {
        uint256 refundableUntil = block.timestamp + depositRefundTimeout;
        bytes32 depositHash = _getDepositHash(msg.sender, token, tokenAmount, unitAmount, refundableUntil);

        // Requirements: deposit hash is not set
        require(!syncDepositHashes[depositHash], Aera__HashCollision());
        // Effects: set hash as used
        syncDepositHashes[depositHash] = true;

        // Effects: set user refundable until
        userUnitsRefundableUntil[msg.sender] = refundableUntil;

        // Interactions: enter vault
        IMultiDepositorVault(MULTI_DEPOSITOR_VAULT).enter(msg.sender, token, tokenAmount, unitAmount, msg.sender);

        // Log emit deposit event
        emit Deposited(msg.sender, token, tokenAmount, unitAmount, depositHash);
    }

    /// @notice Solves an async deposit request for the vault, transfering tokens or refunding as needed
    /// @dev
    /// - Returns 0 if any of:
    ///   - price age is too high, emits PriceAgeExceeded
    ///   - request hash is not set, emits InvalidRequestHash
    ///   - units out is less than min required, emits AmountBoundExceeded
    ///   - deposit cap would be exceeded, emits DepositCapExceeded
    /// - If deadline not passed, processes deposit and emits DepositSolved
    /// - If deadline passed, refunds and emits DepositRefunded
    /// - Always unsets hash after processing
    /// @param token The ERC20 token being deposited
    /// @param depositMultiplier The multiplier (in BPS) applied to the deposit for premium calculation
    /// @param request The deposit request struct containing all user parameters
    /// @param priceAge The age of the price data used for conversion
    /// @param index The index of the request in the given solving batch
    /// @return solverTip The tip amount paid to the solver, or 0 if not processed
    function _solveDepositVaultAutoPrice(
        IERC20 token,
        uint256 depositMultiplier,
        Request calldata request,
        uint256 priceAge,
        uint256 index
    ) internal returns (uint256 solverTip) {
        // Requirements: price age is within user specified max price age
        if (_guardPriceAge(priceAge, request.maxPriceAge, index)) return 0;

        bytes32 depositHash = _getRequestHash(token, request);
        // Requirements: hash has been set
        if (_guardInvalidRequestHash(asyncDepositHashes[depositHash], depositHash)) return 0;

        if (request.deadline >= block.timestamp) {
            solverTip = request.solverTip;
            uint256 tokens = request.tokens;

            // Requirements: tokens are enough for tip
            if (_guardInsufficientTokensForTip(tokens, solverTip, index)) return 0;

            uint256 tokensAfterTip;
            unchecked {
                tokensAfterTip = tokens - solverTip;
            }

            // Interactions: apply premium and convert tokens in to units out
            uint256 unitsOut = _tokensToUnitsFloorIfActive(token, tokensAfterTip, depositMultiplier);
            // Requirements: units out meets min units out
            if (_guardAmountBound(unitsOut, request.units, index)) return 0;
            // Requirements + interactions: convert new total units to numeraire and check against deposit cap
            if (_guardDepositCapExceeded(unitsOut, index)) return 0;

            // Effects: unset hash as used
            asyncDepositHashes[depositHash] = false;
            // Interactions: enter vault
            IMultiDepositorVault(MULTI_DEPOSITOR_VAULT).enter(
                address(this), token, tokensAfterTip, unitsOut, request.user
            );

            // Log emit deposit solved event
            emit DepositSolved(depositHash);
        } else {
            // Effects: unset hash as used
            asyncDepositHashes[depositHash] = false;
            // Interactions: transfer tokens from provisioner to sender
            token.safeTransfer(request.user, request.tokens);
            // Log emit deposit refunded event
            emit DepositRefunded(depositHash);
        }
    }

    /// @notice Solves a fixed price deposit request for the vault, transfering tokens or refunding as needed
    /// @dev User gets exactly min units out, but may over‑fund, the difference is paid to the solver as a tip
    /// @dev
    /// - Returns 0 if any of:
    ///   - price age is too high, emits PriceAgeExceeded
    ///   - request hash is not set, emits InvalidRequestHash
    ///   - tokens needed exceed the maximum allowed, emits AmountBoundExceeded
    ///   - deposit cap would be exceeded, emits DepositCapExceeded
    /// - If deadline not passed, processes deposit and emits DepositSolved
    /// - If deadline passed, refunds and emits DepositRefunded
    /// - Always unsets hash after processing
    /// @param token The ERC20 token being deposited
    /// @param depositMultiplier The multiplier (in BPS) applied to the deposit for premium calculation
    /// @param request The deposit request struct containing all user parameters
    /// @param priceAge The age of the price data used for conversion
    /// @param index The index of the request in the given solving batch
    /// @return solverTip The tip amount paid to the solver, or 0 if not processed
    function _solveDepositVaultFixedPrice(
        IERC20 token,
        uint256 depositMultiplier,
        Request calldata request,
        uint256 priceAge,
        uint256 index
    ) internal returns (uint256 solverTip) {
        // Requirements: price age is within user specified max price age
        if (_guardPriceAge(priceAge, request.maxPriceAge, index)) return 0;

        bytes32 depositHash = _getRequestHash(token, request);
        // Requirements: hash has been set
        if (_guardInvalidRequestHash(asyncDepositHashes[depositHash], depositHash)) return 0;

        if (request.deadline >= block.timestamp) {
            // Interactions: convert units to tokens applying premium
            uint256 tokensNeeded = _unitsToTokensCeilIfActive(token, request.units, depositMultiplier);
            // Requirements: tokens needed is less than or equal to max tokens in
            if (_guardAmountBound(request.tokens, tokensNeeded, index)) return 0;
            // Requirements + interactions: convert new total units to numeraire and check against deposit cap
            if (_guardDepositCapExceeded(request.units, index)) return 0;

            // Effects: unset hash as used
            asyncDepositHashes[depositHash] = false;
            // Interactions: enter vault
            IMultiDepositorVault(MULTI_DEPOSITOR_VAULT).enter(
                address(this), token, tokensNeeded, request.units, request.user
            );

            unchecked {
                solverTip = request.tokens - tokensNeeded;
            }

            // Log emit deposit solved event
            emit DepositSolved(depositHash);
        } else {
            // Effects: unset hash as used
            asyncDepositHashes[depositHash] = false;
            // Interactions: transfer tokens from provisioner to sender
            token.safeTransfer(request.user, request.tokens);
            // Log emit deposit refunded event
            emit DepositRefunded(depositHash);
        }
    }

    /// @notice Solves an async redeem request for the vault, transfering tokens or refunding as needed
    /// @dev
    /// - Returns 0 if any of:
    ///   - price age is too high, emits PriceAgeExceeded
    ///   - request hash is not set, emits InvalidRequestHash
    ///   - token out after premium is less than min required, emits AmountBoundExceeded
    /// - If deadline not passed, processes redeem and emits RedeemSolved
    /// - If deadline passed, refunds and emits RedeemRefunded
    /// - Always unsets hash after processing
    /// @param token The ERC20 token being redeemed
    /// @param redeemMultiplier The multiplier (in BPS) applied to the redeem for premium calculation
    /// @param request The redeem request struct containing all user parameters
    /// @param priceAge The age of the price data used for conversion
    /// @param index The index of the request in the given solving batch
    /// @return solverTip The tip amount paid to the solver, or 0 if not processed
    function _solveRedeemVaultAutoPrice(
        IERC20 token,
        uint256 redeemMultiplier,
        Request calldata request,
        uint256 priceAge,
        uint256 index
    ) internal returns (uint256 solverTip) {
        // Requirements: price age is within user specified max price age
        if (_guardPriceAge(priceAge, request.maxPriceAge, index)) return 0;

        bytes32 redeemHash = _getRequestHash(token, request);
        // Requirements: hash has been set
        if (_guardInvalidRequestHash(asyncRedeemHashes[redeemHash], redeemHash)) return 0;

        if (request.deadline >= block.timestamp) {
            solverTip = request.solverTip;

            // Interactions: convert units to token amount
            uint256 tokenOut = _unitsToTokensFloorIfActive(token, request.units, redeemMultiplier);
            // Requirements: tokens are enough for tip
            if (_guardInsufficientTokensForTip(tokenOut, solverTip, index)) return 0;

            uint256 tokenOutAfterTip;
            unchecked {
                tokenOutAfterTip = tokenOut - solverTip;
            }

            // Requirements: token amount is greater than or equal to net token amount
            if (_guardAmountBound(tokenOutAfterTip, request.tokens, index)) return 0;

            // Effects: unset hash as used
            asyncRedeemHashes[redeemHash] = false;
            // Interactions: exit vault
            IMultiDepositorVault(MULTI_DEPOSITOR_VAULT).exit(
                address(this), token, tokenOut, request.units, address(this)
            );

            // Interactions: transfer tokens from provisioner to sender
            token.safeTransfer(request.user, tokenOutAfterTip);

            // Log emit redeem solved event
            emit RedeemSolved(redeemHash);
        } else {
            // Effects: unset hash as used
            asyncRedeemHashes[redeemHash] = false;
            // Interactions: transfer units from provisioner to sender
            IERC20(MULTI_DEPOSITOR_VAULT).safeTransfer(request.user, request.units);
            // Log emit redeem refunded event
            emit RedeemRefunded(redeemHash);
        }
    }

    /// @notice Solves a fixed price redeem request for the vault, transfering tokens or refunding as needed
    /// @dev User gets exactly min tokens out, but may under‑fund, the difference is paid to the solver as a tip
    /// @dev
    /// - Returns 0 if any of:
    ///   - price age is too high, emits PriceAgeExceeded
    ///   - request hash is not set, emits InvalidRequestHash
    /// - If deadline not passed, processes redeem and emits RedeemSolved
    /// - If deadline passed, refunds and emits RedeemRefunded
    /// - Always unsets hash after processing
    /// @param token The ERC20 token being redeemed
    /// @param redeemMultiplier The multiplier (in BPS) applied to the redeem for premium calculation
    /// @param request The redeem request struct containing all user parameters
    /// @param priceAge The age of the price data used for conversion
    /// @param index The index of the request in the given solving batch
    /// @return solverTip The tip amount paid to the solver, or 0 if not processed
    function _solveRedeemVaultFixedPrice(
        IERC20 token,
        uint256 redeemMultiplier,
        Request calldata request,
        uint256 priceAge,
        uint256 index
    ) internal returns (uint256 solverTip) {
        // Requirements: price age is within user specified max price age
        if (_guardPriceAge(priceAge, request.maxPriceAge, index)) return 0;

        bytes32 redeemHash = _getRequestHash(token, request);
        // Requirements: hash has been set
        if (_guardInvalidRequestHash(asyncRedeemHashes[redeemHash], redeemHash)) return 0;

        if (request.deadline >= block.timestamp) {
            // Interactions: convert units to token amount
            uint256 tokenOut = _unitsToTokensFloorIfActive(token, request.units, redeemMultiplier);
            // Requirements: token amount is greater than or equal to net token amount
            if (_guardAmountBound(tokenOut, request.tokens, index)) return 0;

            // Effects: unset hash as used
            asyncRedeemHashes[redeemHash] = false;
            // Interactions: exit vault
            IMultiDepositorVault(MULTI_DEPOSITOR_VAULT).exit(
                address(this), token, tokenOut, request.units, address(this)
            );
            // Interactions: transfer tokens from provisioner to sender
            token.safeTransfer(request.user, request.tokens);

            unchecked {
                solverTip = tokenOut - request.tokens;
            }

            // Log emit redeem solved event
            emit RedeemSolved(redeemHash);
        } else {
            // Effects: unset hash as used
            asyncRedeemHashes[redeemHash] = false;
            // Interactions: transfer units from provisioner to sender
            IERC20(MULTI_DEPOSITOR_VAULT).safeTransfer(request.user, request.units);
            // Log emit redeem refunded event
            emit RedeemRefunded(redeemHash);
        }
    }

    /// @notice Solves a direct deposit request, transfering tokens and units between users
    /// @dev
    /// - Returns early if any of:
    ///   - request hash is not set, emits InvalidRequestHash
    /// - If deadline not passed, transfers units and tokens, emits DepositSolved
    /// - If deadline passed, refunds tokens, emits DepositRefunded
    /// - Always unsets hash after processing
    /// @param token The ERC20 token being deposited
    /// @param request The deposit request struct containing all user parameters
    function _solveDepositDirect(IERC20 token, Request calldata request) internal {
        bytes32 depositHash = _getRequestHash(token, request);
        // Requirements: hash has been set
        if (!asyncDepositHashes[depositHash]) {
            // Log emit invalid async deposit hash event
            emit InvalidRequestHash(depositHash);
            return;
        }

        // Effects: unset hash as used
        asyncDepositHashes[depositHash] = false;

        if (request.deadline >= block.timestamp) {
            // Interactions: pull units from sender(solver) to user
            IERC20(MULTI_DEPOSITOR_VAULT).safeTransferFrom(msg.sender, request.user, request.units);

            // Interactions: transfer tokens from provisioner to sender
            token.safeTransfer(msg.sender, request.tokens);

            // Log emit deposit solved event
            emit DepositSolved(depositHash);
        } else {
            // Interactions: transfer tokens from provisioner to sender
            token.safeTransfer(request.user, request.tokens);

            // Log emit deposit refunded event
            emit DepositRefunded(depositHash);
        }
    }

    /// @notice Solves a direct redeem request, transfering tokens and units between users
    /// @dev
    /// - Returns early if:
    ///   - request hash is not set, emits InvalidRequestHash
    /// - If deadline not passed, transfers units and tokens, emits RedeemSolved
    /// - If deadline passed, refunds units, emits RedeemRefunded
    /// - Always unsets hash after processing
    /// @param token The ERC20 token being redeemed
    /// @param request The redeem request struct containing all user parameters
    function _solveRedeemDirect(IERC20 token, Request calldata request) internal {
        bytes32 redeemHash = _getRequestHash(token, request);
        // Requirements: hash has been set
        if (!asyncRedeemHashes[redeemHash]) {
            // Log emit invalid async redeem hash event
            emit InvalidRequestHash(redeemHash);
            return;
        }

        // Effects: unset hash as used
        asyncRedeemHashes[redeemHash] = false;

        if (request.deadline >= block.timestamp) {
            // Interactions: transfer units from provisioner to sender
            IERC20(MULTI_DEPOSITOR_VAULT).safeTransfer(msg.sender, request.units);

            // Interactions: pull tokens from sender(solver) to user
            token.safeTransferFrom(msg.sender, request.user, request.tokens);

            // Log emit redeem solved event
            emit RedeemSolved(redeemHash);
        } else {
            // Interactions: transfer units from provisioner to sender
            IERC20(MULTI_DEPOSITOR_VAULT).safeTransfer(request.user, request.units);

            // Log emit redeem refunded event
            emit RedeemRefunded(redeemHash);
        }
    }

    /// @notice Checks if the price age exceeds the maximum allowed and emits an event if so
    /// @param priceAge The difference between when price was measured and submitted onchain
    /// @param maxPriceAge The maximum allowed price age
    /// @param index The index of the request in the given solving batch
    /// @return True if price age is too high, false otherwise
    function _guardPriceAge(uint256 priceAge, uint256 maxPriceAge, uint256 index) internal returns (bool) {
        if (priceAge > maxPriceAge) {
            emit PriceAgeExceeded(index);
            return true;
        }
        return false;
    }

    /// @notice Checks if the request hash exists and emits an event if not
    /// @param hashExists Whether the hash exists
    /// @param requestHash The request hash
    /// @return True if hash does not exist, false otherwise
    function _guardInvalidRequestHash(bool hashExists, bytes32 requestHash) internal returns (bool) {
        if (!hashExists) {
            // Log emit invalid request hash event
            emit InvalidRequestHash(requestHash);
            return true;
        }
        return false;
    }

    /// @notice Checks if there are enough tokens for the solver tip and emits an event if not
    /// @param tokens The number of tokens
    /// @param solverTip The solver tip amount
    /// @param index The index of the request in the given solving batch
    /// @return True if not enough tokens for tip, false otherwise
    function _guardInsufficientTokensForTip(uint256 tokens, uint256 solverTip, uint256 index) internal returns (bool) {
        if (tokens < solverTip) {
            // Log emit insufficient tokens for tip event
            emit InsufficientTokensForTip(index);
            return true;
        }
        return false;
    }

    /// @notice Checks if the amount is less than the bound and emits an event if so
    /// @param amount The actual amount
    /// @param bound The minimum required amount
    /// @param index The index of the request in the given solving batch
    /// @return True if amount is less than bound, false otherwise
    function _guardAmountBound(uint256 amount, uint256 bound, uint256 index) internal returns (bool) {
        if (amount < bound) {
            // Log emit amount bound exceeded event
            emit AmountBoundExceeded(index, amount, bound);
            return true;
        }
        return false;
    }

    /// @notice Checks if the deposit cap would be exceeded and emits an event if so
    /// @param totalUnits The total units after deposit
    /// @param index The index of the request in the given solving batch
    /// @return True if deposit cap would be exceeded, false otherwise
    function _guardDepositCapExceeded(uint256 totalUnits, uint256 index) internal returns (bool) {
        // Interactions: check if deposit cap would be exceeded
        if (_isDepositCapExceeded(totalUnits)) {
            // Log emit deposit cap exceeded event
            emit DepositCapExceeded(index);
            return true;
        }
        return false;
    }

    /// @notice Reverts if sync deposits are not enabled for the token
    /// @param token The ERC20 token to check
    /// @return tokenDetails The token details storage reference
    function _requireSyncDepositsEnabled(IERC20 token) internal view returns (TokenDetails storage tokenDetails) {
        tokenDetails = tokensDetails[token];
        // Requirements: sync deposits are enabled
        require(tokenDetails.syncDepositEnabled, Aera__SyncDepositDisabled());
    }

    /// @notice Reverts if deposit cap would be exceeded by adding units
    /// @param units The number of units to add
    function _requireDepositCapNotExceeded(uint256 units) internal view {
        // Requirements + interactions: deposit cap not exceeded
        require(!_isDepositCapExceeded(units), Aera__DepositCapExceeded());
    }

    /// @notice Checks if deposit cap would be exceeded by adding units
    /// @param units The number of units to add
    /// @return True if deposit cap would be exceeded, false otherwise
    function _isDepositCapExceeded(uint256 units) internal view returns (bool) {
        // Interactions: get current total supply
        uint256 newTotal = IERC20(MULTI_DEPOSITOR_VAULT).totalSupply() + units;
        // Interactions: convert total supply to numeraire
        return PRICE_FEE_CALCULATOR.convertUnitsToNumeraire(MULTI_DEPOSITOR_VAULT, newTotal) > depositCap;
    }

    /// @notice Converts token amount to units, applying multiplier and flooring
    /// @param token The ERC20 token
    /// @param tokens The amount of tokens
    /// @param multiplier The multiplier to apply
    /// @return The resulting units (floored)
    function _tokensToUnitsFloorIfActive(IERC20 token, uint256 tokens, uint256 multiplier)
        internal
        view
        returns (uint256)
    {
        uint256 tokensAdjusted = tokens * multiplier / ONE_IN_BPS;
        // Interactions: convert tokens to units
        return PRICE_FEE_CALCULATOR.convertTokenToUnitsIfActive(
            MULTI_DEPOSITOR_VAULT, token, tokensAdjusted, Math.Rounding.Floor
        );
    }

    /// @notice Converts units to token amount, applying multiplier and flooring
    /// @param token The ERC20 token
    /// @param units The amount of units
    /// @param multiplier The multiplier to apply
    /// @return The resulting token amount (floored)
    function _unitsToTokensFloorIfActive(IERC20 token, uint256 units, uint256 multiplier)
        internal
        view
        returns (uint256)
    {
        // Interactions: convert units to tokens
        uint256 tokensAmount =
            PRICE_FEE_CALCULATOR.convertUnitsToTokenIfActive(MULTI_DEPOSITOR_VAULT, token, units, Math.Rounding.Floor);
        return tokensAmount * multiplier / ONE_IN_BPS;
    }

    /// @notice Converts units to token amount, applying multiplier and ceiling
    /// @param token The ERC20 token
    /// @param units The amount of units
    /// @param multiplier The multiplier to apply
    /// @return The resulting token amount (ceiled)
    function _unitsToTokensCeilIfActive(IERC20 token, uint256 units, uint256 multiplier)
        internal
        view
        returns (uint256)
    {
        // Interactions: convert units to tokens
        uint256 tokensAmount =
            PRICE_FEE_CALCULATOR.convertUnitsToTokenIfActive(MULTI_DEPOSITOR_VAULT, token, units, Math.Rounding.Ceil);
        return Math.mulDiv(tokensAmount, ONE_IN_BPS, multiplier, Math.Rounding.Ceil);
    }

    /// @notice Get the hash of a deposit
    /// @param user The user who made the deposit
    /// @param token The token that was deposited
    /// @param tokenAmount The amount of tokens deposited
    /// @param unitsAmount The amount of units received
    /// @param refundableUntil The timestamp at which the deposit can be refunded
    /// @return The hash of the deposit
    /// @dev Since refundableUntil is block.timestamp + depositRefundTimeout (which is subject to change), it's
    /// theoretically possible to have a hash collision, but the probability is negligible and we optimize for the
    /// common case
    function _getDepositHash(
        address user,
        IERC20 token,
        uint256 tokenAmount,
        uint256 unitsAmount,
        uint256 refundableUntil
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, token, tokenAmount, unitsAmount, refundableUntil));
    }

    /// @notice Get the hash of a request from parameters
    /// @param token The token that was deposited or redeemed
    /// @param user The user who made the request
    /// @param requestType The type of request
    /// @param tokens The amount of tokens in the request
    /// @param units The amount of units in the request
    /// @param solverTip The tip paid to the solver
    /// @param deadline The deadline of the request
    /// @param maxPriceAge The maximum age of the price data
    /// @return The hash of the request
    function _getRequestHashParams(
        IERC20 token,
        address user,
        RequestType requestType,
        uint256 tokens,
        uint256 units,
        uint256 solverTip,
        uint256 deadline,
        uint256 maxPriceAge
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token, user, requestType, tokens, units, solverTip, deadline, maxPriceAge));
    }

    /// @notice Get the hash of a request
    /// @param token The token that was deposited or redeemed
    /// @param request The request to get the hash of
    /// @return The hash of the request
    function _getRequestHash(IERC20 token, Request calldata request) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                token,
                request.user,
                request.requestType,
                request.tokens,
                request.units,
                request.solverTip,
                request.deadline,
                request.maxPriceAge
            )
        );
    }

    /// @notice Returns true if the request type is a deposit
    /// @param requestType The request type
    /// @return True if deposit, false otherwise
    function _isRequestTypeDeposit(RequestType requestType) internal pure returns (bool) {
        return uint8(requestType) & DEPOSIT_REDEEM_FLAG == 0;
    }

    /// @notice Returns true if the request type is fixed price
    /// @param requestType The request type
    /// @return True if fixed price, false otherwise
    function _isRequestTypeAutoPrice(RequestType requestType) internal pure returns (bool) {
        return uint8(requestType) & AUTO_PRICE_FIXED_PRICE_FLAG == 0;
    }
}