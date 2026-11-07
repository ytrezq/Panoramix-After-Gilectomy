// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IAlchemistV3} from "../interfaces/IAlchemistV3.sol";
import {IAlchemistV3Position} from "../interfaces/IAlchemistV3Position.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IVaultV2} from "../../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {ITransmuter} from "../interfaces/ITransmuter.sol";

/// @title  AlchemistRouter
/// @notice Batches multi-step Alchemist operations (deposit, borrow, repay, withdraw, self-liquidate, claim) into single transactions for EOA users.
/// @dev    Holds no user funds between transactions. Alchemist is set at construction via immutable.
contract AlchemistRouter is ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    address public immutable alchemist;

    /// @dev Flag to allow receiving ETH from WETH unwrap during withdraw flows.
    bool private transient _ethExpected;

    /// @param _alchemist The Alchemist contract this router interacts with.
    constructor(address _alchemist) {
        require(_alchemist != address(0), "Zero address");

        alchemist = _alchemist;
    }

    /// @notice Deposit underlying token into MYT vault + Alchemist, optionally borrow.
    /// @dev    Caller must have approved this contract for `amount` of underlying.
    ///         Pass `tokenId = 0` to create a new position, or an existing token ID to deposit into it.
    ///         For existing positions: caller must own the NFT (it stays with the caller).
    ///         If `borrowAmount` > 0 on an existing position, caller must have called
    ///         `approveMint(tokenId, router, borrowAmount)` on the Alchemist.
    /// @param  tokenId       Position NFT token ID (0 to create a new position).
    /// @param  amount        Amount of underlying token to deposit.
    /// @param  borrowAmount  Amount of debt tokens to borrow (0 to skip borrowing).
    /// @param  minSharesOut  Minimum MYT shares to receive (slippage protection).
    /// @param  deadline      Timestamp after which the transaction reverts.
    /// @return                The position NFT token ID (newly minted or same as input).
    function depositUnderlying(
        uint256 tokenId,
        uint256 amount,
        uint256 borrowAmount,
        uint256 minSharesOut,
        uint256 deadline
    ) external nonReentrant returns (uint256) {
        require(block.timestamp <= deadline, "Expired");
        require(amount > 0, "Zero amount");

        address mytVault = IAlchemistV3(alchemist).myt();
        address underlying = IAlchemistV3(alchemist).underlyingToken();

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(underlying).forceApprove(mytVault, amount);

        uint256 shares = IVaultV2(mytVault).deposit(amount, address(this));
        require(shares >= minSharesOut, "Slippage");

        IERC20(underlying).forceApprove(mytVault, 0);

        return _depositAndBorrow(mytVault, shares, tokenId, borrowAmount);
    }

    /// @notice Deposit native ETH → WETH → MYT vault → Alchemist, optionally borrow.
    /// @dev    Requires the Alchemist's underlyingToken to be WETH.
    ///         Pass `tokenId = 0` to create a new position, or an existing token ID to deposit into it.
    ///         For existing positions: caller must own the NFT (it stays with the caller).
    ///         If `borrowAmount` > 0 on an existing position, caller must have called
    ///         `approveMint(tokenId, router, borrowAmount)` on the Alchemist.
    /// @param  tokenId       Position NFT token ID (0 to create a new position).
    /// @param  borrowAmount  Amount of debt tokens to borrow (0 to skip borrowing).
    /// @param  minSharesOut  Minimum MYT shares to receive (slippage protection).
    /// @param  deadline      Timestamp after which the transaction reverts.
    /// @return                The position NFT token ID (newly minted or same as input).
    function depositETH(
        uint256 tokenId,
        uint256 borrowAmount,
        uint256 minSharesOut,
        uint256 deadline
    ) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "No ETH sent");
        require(block.timestamp <= deadline, "Expired");

        address mytVault = IAlchemistV3(alchemist).myt();
        address underlying = IAlchemistV3(alchemist).underlyingToken();

        IWETH(underlying).deposit{value: msg.value}();
        IERC20(underlying).forceApprove(mytVault, msg.value);

        uint256 shares = IVaultV2(mytVault).deposit(msg.value, address(this));
        require(shares >= minSharesOut, "Slippage");

        IERC20(underlying).forceApprove(mytVault, 0);

        return _depositAndBorrow(mytVault, shares, tokenId, borrowAmount);
    }

    /// @notice Deposit MYT shares directly into Alchemist, optionally borrow.
    /// @dev    Caller must have approved this contract for `shares` of MYT.
    ///         Pass `tokenId = 0` to create a new position, or an existing token ID to deposit into it.
    ///         For existing positions: caller must own the NFT (it stays with the caller).
    ///         If `borrowAmount` > 0 on an existing position, caller must have called
    ///         `approveMint(tokenId, router, borrowAmount)` on the Alchemist.
    /// @param  tokenId       Position NFT token ID (0 to create a new position).
    /// @param  shares        Amount of MYT shares to deposit.
    /// @param  borrowAmount  Amount of debt tokens to borrow (0 to skip borrowing).
    /// @param  deadline      Timestamp after which the transaction reverts.
    /// @return                The position NFT token ID (newly minted or same as input).
    function depositMYT(
        uint256 tokenId,
        uint256 shares,
        uint256 borrowAmount,
        uint256 deadline
    ) external nonReentrant returns (uint256) {
        require(block.timestamp <= deadline, "Expired");
        require(shares > 0, "Zero shares");

        address mytVault = IAlchemistV3(alchemist).myt();

        IERC20(mytVault).safeTransferFrom(msg.sender, address(this), shares);

        return _depositAndBorrow(mytVault, shares, tokenId, borrowAmount);
    }

    /// @notice Deposit ETH into MYT vault only (no Alchemist position).
    ///         MYT shares are sent directly to the caller.
    /// @dev    Requires the Alchemist's underlyingToken to be WETH.
    /// @param  minSharesOut  Minimum MYT shares to receive (slippage protection).
    /// @param  deadline      Timestamp after which the transaction reverts.
    /// @return shares        MYT shares received.
    function depositETHToVaultOnly(
        uint256 minSharesOut,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 shares) {
        require(msg.value > 0, "No ETH sent");
        require(block.timestamp <= deadline, "Expired");

        address mytVault = IAlchemistV3(alchemist).myt();
        address underlying = IAlchemistV3(alchemist).underlyingToken();

        IWETH(underlying).deposit{value: msg.value}();
        IERC20(underlying).forceApprove(mytVault, msg.value);
        shares = IVaultV2(mytVault).deposit(msg.value, msg.sender);

        // Clear residual approval before slippage check so it runs on all paths
        IERC20(underlying).forceApprove(mytVault, 0);

        require(shares >= minSharesOut, "Slippage");
    }

    // ─── Repay ───────────────────────────────────────────────────────────

    /// @notice Repay debt on a position using underlying tokens.
    /// @dev    Caller must have approved this contract for `amount` of underlying.
    ///         Any MYT shares not consumed by the repayment are returned to the caller.
    /// @param  recipientTokenId  The position NFT token ID to repay debt on.
    /// @param  amount            Amount of underlying token to use for repayment.
    /// @param  minSharesOut      Minimum MYT shares from vault deposit (slippage protection).
    /// @param  deadline          Timestamp after which the transaction reverts.
    function repayUnderlying(
        uint256 recipientTokenId,
        uint256 amount,
        uint256 minSharesOut,
        uint256 deadline
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Expired");
        require(amount > 0, "Zero amount");

        address mytVault = IAlchemistV3(alchemist).myt();
        address underlying = IAlchemistV3(alchemist).underlyingToken();

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(underlying).forceApprove(mytVault, amount);

        uint256 shares = IVaultV2(mytVault).deposit(amount, address(this));
        require(shares >= minSharesOut, "Slippage");

        IERC20(underlying).forceApprove(mytVault, 0);

        _repayAndRefund(mytVault, shares, recipientTokenId);
    }

    /// @notice Repay debt on a position using native ETH.
    /// @dev    Requires the Alchemist's underlyingToken to be WETH.
    ///         Any MYT shares not consumed by the repayment are returned to the caller
    ///         as MYT vault shares (not ETH). Callers must redeem shares separately if
    ///         they want the underlying back.
    /// @param  recipientTokenId  The position NFT token ID to repay debt on.
    /// @param  minSharesOut      Minimum MYT shares from vault deposit (slippage protection).
    /// @param  deadline          Timestamp after which the transaction reverts.
    function repayETH(
        uint256 recipientTokenId,
        uint256 minSharesOut,
        uint256 deadline
    ) external payable nonReentrant {
        require(msg.value > 0, "No ETH sent");
        require(block.timestamp <= deadline, "Expired");

        address mytVault = IAlchemistV3(alchemist).myt();
        address underlying = IAlchemistV3(alchemist).underlyingToken();

        IWETH(underlying).deposit{value: msg.value}();
        IERC20(underlying).forceApprove(mytVault, msg.value);

        uint256 shares = IVaultV2(mytVault).deposit(msg.value, address(this));
        require(shares >= minSharesOut, "Slippage");

        IERC20(underlying).forceApprove(mytVault, 0);

        _repayAndRefund(mytVault, shares, recipientTokenId);
    }

    // ─── Withdraw ────────────────────────────────────────────────────────

    /// @notice Withdraw MYT shares from Alchemist, redeem to underlying, send to caller.
    /// @dev    Caller must approve this contract for the position NFT (ERC721 approve).
    ///         NFT is temporarily held by the router and returned after withdraw.
    ///         WARNING: The NFT round-trip resets ALL mint allowances (approveMint) on this position.
    /// @param  tokenId       The position NFT token ID to withdraw from.
    /// @param  shares        Amount of MYT shares to withdraw from the Alchemist.
    /// @param  minAmountOut  Minimum underlying tokens to receive (slippage protection on vault redeem).
    /// @param  deadline      Timestamp after which the transaction reverts.
    function withdrawUnderlying(
        uint256 tokenId,
        uint256 shares,
        uint256 minAmountOut,
        uint256 deadline
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Expired");
        require(shares > 0, "Zero shares");
        require(tokenId != 0, "Invalid tokenId");

        _withdraw(tokenId, shares, minAmountOut, false);
    }

    /// @notice Withdraw MYT shares from Alchemist, redeem to WETH, unwrap, send ETH to caller.
    /// @dev    Caller must approve this contract for the position NFT (ERC721 approve).
    ///         NFT is temporarily held by the router and returned after withdraw.
    ///         WARNING: The NFT round-trip resets ALL mint allowances (approveMint) on this position.
    /// @param  tokenId       The position NFT token ID to withdraw from.
    /// @param  shares        Amount of MYT shares to withdraw from the Alchemist.
    /// @param  minAmountOut  Minimum ETH to receive (slippage protection on vault redeem).
    /// @param  deadline      Timestamp after which the transaction reverts.
    function withdrawETH(
        uint256 tokenId,
        uint256 shares,
        uint256 minAmountOut,
        uint256 deadline
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Expired");
        require(shares > 0, "Zero shares");
        require(tokenId != 0, "Invalid tokenId");

        _withdraw(tokenId, shares, minAmountOut, true);
    }

    /// @notice Self-liquidate a position: burn debt, redeem remaining collateral to underlying, send to caller.
    /// @dev    Caller must approve this contract for the position NFT (ERC721 approve).
    ///         NFT is temporarily held by the router and returned after self-liquidation.
    ///         WARNING: The NFT round-trip resets ALL mint allowances (approveMint) on this position.
    /// @param  tokenId       The position NFT token ID to self-liquidate.
    /// @param  minAmountOut  Minimum underlying tokens to receive (slippage protection on vault redeem).
    /// @param  deadline      Timestamp after which the transaction reverts.
    function selfLiquidateToUnderlying(
        uint256 tokenId,
        uint256 minAmountOut,
        uint256 deadline
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Expired");
        require(tokenId != 0, "Invalid tokenId");

        _selfLiquidate(tokenId, minAmountOut, false);
    }

    /// @notice Self-liquidate a position: burn debt, redeem remaining collateral to ETH, send to caller.
    /// @dev    Caller must approve this contract for the position NFT (ERC721 approve).
    ///         NFT is temporarily held by the router and returned after self-liquidation.
    ///         WARNING: The NFT round-trip resets ALL mint allowances (approveMint) on this position.
    /// @param  tokenId       The position NFT token ID to self-liquidate.
    /// @param  minAmountOut  Minimum ETH to receive (slippage protection on vault redeem).
    /// @param  deadline      Timestamp after which the transaction reverts.
    function selfLiquidateToETH(
        uint256 tokenId,
        uint256 minAmountOut,
        uint256 deadline
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Expired");
        require(tokenId != 0, "Invalid tokenId");

        _selfLiquidate(tokenId, minAmountOut, true);
    }

    // ─── Transmuter Claim ────────────────────────────────────────────────

    /// @notice Claim a matured transmuter position, redeem MYT shares, and send proceeds to caller.
    /// @dev    Caller must approve this contract for the transmuter position NFT (ERC721 approve).
    ///         The transmuter burns the NFT on claim. Any untransmuted synthetic tokens
    ///         are forwarded to the caller as-is.
    ///         When `unwrapETH` is true, redeemed WETH is unwrapped and sent as native ETH.
    /// @param  positionId      The transmuter position NFT token ID to claim.
    /// @param  minAmountOut    Minimum underlying tokens (or ETH if unwrapETH) to receive (slippage protection).
    /// @param  deadline        Timestamp after which the transaction reverts.
    /// @param  unwrapETH       If true, redeem to WETH and unwrap to native ETH before sending.
    function claimRedemption(
        uint256 positionId,
        uint256 minAmountOut,
        uint256 deadline,
        bool unwrapETH
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Expired");
        _claimRedemption(positionId, minAmountOut, unwrapETH);
    }

    // ─── Internal ────────────────────────────────────────────────────────

    /// @dev Unified deposit + optional borrow logic.
    ///      Assumes MYT shares are already in this contract.
    ///      When tokenId == 0: creates a new position (NFT minted to router, then transferred to caller).
    ///      When tokenId != 0: deposits into existing position (NFT stays with caller, uses mintFrom for borrowing).
    function _depositAndBorrow(
        address mytVault,
        uint256 shares,
        uint256 tokenId,
        uint256 borrowAmount
    ) internal returns (uint256) {
        IERC20(mytVault).forceApprove(alchemist, shares);

        IAlchemistV3Position nft = IAlchemistV3Position(IAlchemistV3(alchemist).alchemistPositionNFT());

        if (tokenId == 0) {
            (tokenId, ) = IAlchemistV3(alchemist).deposit(shares, address(this), 0);
            IERC20(mytVault).forceApprove(alchemist, 0);

            if (borrowAmount > 0) {
                IAlchemistV3(alchemist).mint(tokenId, borrowAmount, msg.sender);
            }

            nft.transferFrom(address(this), msg.sender, tokenId);
        } else {
            // Existing position: deposit to caller (NFT owner), borrow via mintFrom
            require(nft.ownerOf(tokenId) == msg.sender, "Not position owner");

            IAlchemistV3(alchemist).deposit(shares, msg.sender, tokenId);
            IERC20(mytVault).forceApprove(alchemist, 0);

            if (borrowAmount > 0) {
                IAlchemistV3(alchemist).mintFrom(tokenId, borrowAmount, msg.sender);
            }
        }

        return tokenId;
    }

    /// @dev Withdraw MYT shares from Alchemist, redeem via vault, and deliver proceeds.
    ///      When unwrapETH is true, redeems WETH to this contract, unwraps, and sends ETH to caller.
    ///      Otherwise redeems underlying directly to caller.
    ///      NFT is temporarily held by the router and returned after withdraw.
    function _withdraw(uint256 tokenId, uint256 shares, uint256 minAmountOut, bool unwrapETH) internal {
        IAlchemistV3Position nft = IAlchemistV3Position(IAlchemistV3(alchemist).alchemistPositionNFT());
        address mytVault = IAlchemistV3(alchemist).myt();

        // Only the position owner may withdraw (not merely an approved operator)
        require(nft.ownerOf(tokenId) == msg.sender, "Not position owner");

        // Take custody of position NFT (caller must have approved router)
        nft.transferFrom(msg.sender, address(this), tokenId);

        // Withdraw MYT shares from Alchemist to this contract
        IAlchemistV3(alchemist).withdraw(shares, address(this), tokenId);

        // Return NFT to caller
        nft.transferFrom(address(this), msg.sender, tokenId);

        _redeemAndDeliver(mytVault, shares, minAmountOut, unwrapETH);
    }

    /// @dev Approve MYT spending by Alchemist, repay, clear approval, refund unused MYT shares to caller.
    ///      Uses balance delta (not absolute balanceOf) to be donation-resistant.
    function _repayAndRefund(
        address mytVault,
        uint256 shares,
        uint256 recipientTokenId
    ) internal {
        IERC20(mytVault).forceApprove(alchemist, shares);

        uint256 balBefore = IERC20(mytVault).balanceOf(address(this));
        IAlchemistV3(alchemist).repay(shares, recipientTokenId);
        uint256 consumed = balBefore - IERC20(mytVault).balanceOf(address(this));

        IERC20(mytVault).forceApprove(alchemist, 0);

        // Return any unused MYT shares (repay caps to outstanding debt)
        uint256 remaining = shares - consumed;
        if (remaining > 0) {
            IERC20(mytVault).safeTransfer(msg.sender, remaining);
        }
    }

    /// @dev Shared claim logic: takes transmuter NFT, claims, forwards synthetic refund, redeems MYT.
    ///      When unwrapETH is true, redeems MYT → WETH → unwrap → send native ETH to caller.
    ///      When unwrapETH is false, redeems MYT → underlying sent directly to caller.
    function _claimRedemption(
        uint256 positionId,
        uint256 minAmountOut,
        bool unwrapETH
    ) internal {
        address transmuter = IAlchemistV3(alchemist).transmuter();
        address mytVault = IAlchemistV3(alchemist).myt();
        address syntheticToken = IAlchemistV3(alchemist).debtToken();

        // Take custody of transmuter NFT (caller must have approved router)
        IERC721(transmuter).transferFrom(msg.sender, address(this), positionId);

        // Claim — transmuter burns the NFT, sends MYT shares + synthetic refund to this contract
        (uint256 claimYield, , uint256 syntheticReturned, ) = ITransmuter(transmuter).claimRedemption(positionId);
        require(claimYield > 0, "No MYT to redeem");

        // Forward any returned synthetic tokens before the untrusted ETH .call
        if (syntheticReturned > 0) {
            IERC20(syntheticToken).safeTransfer(msg.sender, syntheticReturned);
        }

        _redeemAndDeliver(mytVault, claimYield, minAmountOut, unwrapETH);
    }

    /// @dev Self-liquidate a position: take NFT, call selfLiquidate, return NFT, redeem MYT proceeds.
    ///      selfLiquidate burns debt against collateral and sends remaining MYT shares to this contract.
    ///      When unwrapETH is true, redeems MYT → WETH → unwrap → send native ETH to caller.
    ///      Otherwise redeems MYT → underlying sent directly to caller.
    function _selfLiquidate(uint256 tokenId, uint256 minAmountOut, bool unwrapETH) internal {
        IAlchemistV3Position nft = IAlchemistV3Position(IAlchemistV3(alchemist).alchemistPositionNFT());
        address mytVault = IAlchemistV3(alchemist).myt();

        // Only the position owner may self-liquidate (not merely an approved operator)
        require(nft.ownerOf(tokenId) == msg.sender, "Not position owner");

        // Take custody of position NFT (caller must have approved router)
        nft.transferFrom(msg.sender, address(this), tokenId);

        // Self-liquidate — burns debt, sends remaining MYT shares to this contract.
        // Return value is the total collateral consumed for debt repayment, not the remainder we receive.
        uint256 mytBefore = IERC20(mytVault).balanceOf(address(this));
        IAlchemistV3(alchemist).selfLiquidate(tokenId, address(this));
        uint256 mytShares = IERC20(mytVault).balanceOf(address(this)) - mytBefore;

        // If all collateral was consumed by debt, there's nothing to redeem via the router.
        // Users who want to self-liquidate without return collateral can call the Alchemist directly.
        require(mytShares > 0, "No collateral remaining");

        // Return NFT to caller (position is zeroed but NFT still exists)
        nft.transferFrom(address(this), msg.sender, tokenId);

        _redeemAndDeliver(mytVault, mytShares, minAmountOut, unwrapETH);
    }

    /// @dev Redeem MYT shares via vault and deliver proceeds to caller.
    ///      When unwrapETH is true, redeems to this contract, unwraps WETH, sends native ETH.
    ///      Otherwise redeems underlying directly to caller.
    function _redeemAndDeliver(address mytVault, uint256 mytShares, uint256 minAmountOut, bool unwrapETH) internal {
        if (unwrapETH) {
            uint256 assets = IVaultV2(mytVault).redeem(mytShares, address(this), address(this));
            require(assets >= minAmountOut, "Slippage");

            address underlying = IAlchemistV3(alchemist).underlyingToken();

            _ethExpected = true;
            IWETH(underlying).withdraw(assets);
            _ethExpected = false;
            (bool success, ) = msg.sender.call{value: assets}("");
            require(success, "ETH transfer failed");
        } else {
            uint256 assets = IVaultV2(mytVault).redeem(mytShares, msg.sender, address(this));
            require(assets >= minAmountOut, "Slippage");
        }
    }

    /// @dev Accept ETH only from WETH unwrap (withdraw, self-liquidate, and claim flows).
    receive() external payable {
        require(_ethExpected, "Use depositETH");
    }
}
