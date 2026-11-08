// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/* solhint-disable var-name-mixedcase */

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title MockStrcPriceOracle
 * @dev Simple mock for the STRC price oracle used by sUSDat.
 */
contract MockStrcPriceOracle {
    uint256 public price;
    uint8 public priceDecimals;

    constructor(uint256 price_, uint8 decimals_) {
        price = price_;
        priceDecimals = decimals_;
    }

    function getPrice() external view returns (uint256, uint8) {
        return (price, priceDecimals);
    }

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }
}

/**
 * @title MockStakedUSDat
 * @notice Mock of Saturn's StakedUSDat vault for testing the SaturnStrategy.
 *
 * Simulates:
 * - ERC4626 vault with 0.1% deposit fee (depositFeeBps = 10)
 * - 18 decimal shares with _decimalsOffset = 12 (asset is 6 decimals)
 * - STRC vesting (vestingAmount, vestingPeriod, lastDistributionTimestamp)
 * - Async withdrawal queue (requestRedeem → processAllPending → claim)
 * - STRC price oracle for totalAssets calculation
 * - withdraw/redeem disabled (reverts with OperationNotAllowed)
 */
contract MockStakedUSDat is ERC4626 {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public depositFeeBps = 10; // 0.1%
    address public feeRecipient;

    // Vesting state
    uint256 public vestingAmount;
    uint256 public vestingPeriod;
    uint256 public lastDistributionTimestamp;
    uint256 public strcBalance;
    uint256 public usdatBalance;

    // STRC oracle
    MockStrcPriceOracle public strcOracle;

    // Withdrawal queue
    struct WithdrawalRequest {
        address owner;
        uint256 shares;
        uint256 assets;
        bool processed;
        bool claimed;
    }

    uint256 public nextRequestId;
    mapping(uint256 => WithdrawalRequest) public requests;
    mapping(address => uint256[]) public userRequests;

    error OperationNotAllowed();
    error NothingToClaim();

    constructor(
        IERC20 asset_,
        address admin_
    ) ERC4626(asset_) ERC20("Staked USDat", "sUSDat") {
        feeRecipient = admin_;

        // Default: STRC price ~$100 with 8 decimal precision
        strcOracle = new MockStrcPriceOracle(100e8, 8);
    }

    // ============ ERC4626 Overrides ============

    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /// @dev previewDeposit accounts for the deposit fee
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        if (depositFeeBps == 0 || feeRecipient == address(0)) {
            return super.previewDeposit(assets);
        }
        uint256 fee = Math.mulDiv(assets, depositFeeBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
        return super.previewDeposit(assets - fee);
    }

    /// @dev previewMint accounts for the deposit fee
    function previewMint(uint256 shares) public view override returns (uint256) {
        if (depositFeeBps == 0 || feeRecipient == address(0)) {
            return super.previewMint(shares);
        }
        uint256 assets = super.previewMint(shares);
        return Math.mulDiv(assets, BPS_DENOMINATOR, BPS_DENOMINATOR - depositFeeBps, Math.Rounding.Ceil);
    }

    /// @dev _deposit handles fee transfer
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (depositFeeBps > 0 && feeRecipient != address(0)) {
            uint256 fee = Math.mulDiv(assets, depositFeeBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
            IERC20(asset()).safeTransferFrom(caller, feeRecipient, fee);
            uint256 netAssets = assets - fee;
            usdatBalance += netAssets;
            // Standard ERC4626 deposit with net assets
            IERC20(asset()).safeTransferFrom(caller, address(this), netAssets);
            _mint(receiver, shares);
            emit Deposit(caller, receiver, netAssets, shares);
        } else {
            usdatBalance += assets;
            super._deposit(caller, receiver, assets, shares);
        }
    }

    /// @dev Disable standard withdraw/redeem — must use requestRedeem/claim
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert OperationNotAllowed();
    }

    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert OperationNotAllowed();
    }

    function maxWithdraw(address) public pure override returns (uint256) {
        return 0;
    }

    function maxRedeem(address) public pure override returns (uint256) {
        return 0;
    }

    /// @dev totalAssets = usdatBalance + vestedSTRC in USD
    function totalAssets() public view override returns (uint256) {
        return usdatBalance + _strcTotalAssets();
    }

    function _strcTotalAssets() internal view returns (uint256) {
        (uint256 strcPrice, uint8 priceDecimals) = strcOracle.getPrice();
        uint256 unvested = getUnvestedAmount();
        uint256 vestedBalance = strcBalance > unvested ? strcBalance - unvested : 0;
        return Math.mulDiv(vestedBalance, strcPrice, 10 ** priceDecimals, Math.Rounding.Floor);
    }

    // ============ Vesting ============

    function getUnvestedAmount() public view returns (uint256) {
        if (lastDistributionTimestamp == 0 || vestingPeriod == 0) return 0;
        uint256 timeSinceLastDistribution = block.timestamp - lastDistributionTimestamp;
        if (timeSinceLastDistribution >= vestingPeriod) return 0;
        return Math.mulDiv(vestingPeriod - timeSinceLastDistribution, vestingAmount, vestingPeriod, Math.Rounding.Ceil);
    }

    /// @notice Simulate STRC reward distribution (like transferInRewards)
    function transferInRewards(uint256 strcAmount, uint256 period) external {
        vestingAmount = strcAmount;
        vestingPeriod = period;
        lastDistributionTimestamp = block.timestamp;
        strcBalance += strcAmount;
    }

    // ============ Withdrawal Queue ============

    /// @notice Request redemption of sUSDat shares
    function requestRedeem(uint256 shares, uint256 /* minUsdatReceived */) external returns (uint256 requestId) {
        // Transfer shares from caller to this contract (simulates queue holding)
        _transfer(msg.sender, address(this), shares);

        uint256 assets = previewRedeem(shares);
        requestId = nextRequestId++;

        requests[requestId] = WithdrawalRequest({
            owner: msg.sender,
            shares: shares,
            assets: assets,
            processed: false,
            claimed: false
        });
        userRequests[msg.sender].push(requestId);
        return requestId;
    }

    /// @notice Claim all processed withdrawal requests
    function claim() external returns (uint256 totalAmount) {
        uint256[] storage ids = userRequests[msg.sender];
        bool hasClaimed = false;
        for (uint256 i = 0; i < ids.length; i++) {
            WithdrawalRequest storage req = requests[ids[i]];
            if (req.processed && !req.claimed) {
                req.claimed = true;
                totalAmount += req.assets;
                hasClaimed = true;

                // Burn the shares held by this contract
                _burn(address(this), req.shares);
                usdatBalance -= req.assets;
            }
        }
        if (!hasClaimed) revert NothingToClaim();

        IERC20(asset()).safeTransfer(msg.sender, totalAmount);
        return totalAmount;
    }

    function getWithdrawalQueue() external view returns (address) {
        return address(this); // Self-contained mock
    }

    // ============ Oracle ============

    function getStrcOracle() external view returns (address) {
        return address(strcOracle);
    }

    // ============ Test Helpers ============

    /// @notice Process all pending withdrawal requests (test-only)
    function processAllPending() external {
        for (uint256 i = 0; i < nextRequestId; i++) {
            if (!requests[i].processed && !requests[i].claimed) {
                requests[i].processed = true;
            }
        }
    }

    /// @notice Set the mock STRC price (test-only)
    function setMockStrcPrice(uint256 newPrice) external {
        strcOracle.setPrice(newPrice);
    }

    /// @notice Set the deposit fee (test-only)
    function setDepositFeeBps(uint256 feeBps) external {
        depositFeeBps = feeBps;
    }

    /// @notice Set the fee recipient (test-only)
    function setFeeRecipient(address recipient) external {
        feeRecipient = recipient;
    }

    /// @notice Directly set USDat balance (test-only, for simulating yield/loss)
    function setUsdatBalance(uint256 amount) external {
        usdatBalance = amount;
    }

    /// @notice Directly set STRC balance (test-only, for simulating vesting state)
    function setStrcBalance(uint256 amount) external {
        strcBalance = amount;
    }
}
