// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockMToken} from "./MockMToken.sol";
import {MockBaseAsset} from "./MockBaseAsset.sol";
import {MockOracle} from "./MockOracle.sol";
import {
    Request,
    RequestStatus
} from "../../tranches/strategies/midas/interfaces/IRedemptionVault.sol";

/**
 * @title MockRedemptionVault
 * @dev Mock Midas RedemptionVault that accepts redeemInstant and redeemRequest
 */
contract MockRedemptionVault {

    /**
    * @dev Midas
    * @param dataFeed data feed token/USD address
    * @param fee fee by token, 1% = 100
    * @param allowance token allowance (decimals 18)
    */
    struct TokenConfig {
        address dataFeed;
        uint256 fee;
        uint256 allowance;
        bool stable;
    }

    MockMToken public mToken;
    MockBaseAsset public baseAsset;

    uint256 public nextRequestId;
    mapping(uint256 => Request) public _requests;

    /// @dev Controls whether redeemInstant succeeds or reverts
    bool public instantEnabled;

    /**
     * @dev Midas
     * @dev fee for initial operations 1% = 100
     */
    uint256 public instantFee;

    /**
     * @notice mapping, token address to token config
     */
    mapping(address => TokenConfig) public tokensConfig;

    /// @dev Mock rate: 1.05e18 (mToken price in base18)
    uint256 public mTokenRate = 1_050000000000000000;
    /// @dev Mock rate: 1e18 (stablecoin = $1)
    uint256 public tokenOutRate = 1_000000000000000000;

    MockOracle public oracle;

    /**
     * @notice address is designated for standard redemptions, allowing tokens to be pulled from this address
     */
    address public requestRedeemer;


    constructor(MockMToken _mToken, MockBaseAsset _baseAsset) {
        mToken = _mToken;
        baseAsset = _baseAsset;
        instantEnabled = false;
    }

    function currentRequestId () external view returns (uint256) {
        if (nextRequestId == 0) {
            return 0;
        }
        return nextRequestId - 1;
    }

    function setInstantEnabled(bool _enabled) external {
        instantEnabled = _enabled;
    }

    function setRates(uint256 _mTokenRate, uint256 _tokenOutRate) external {
        mTokenRate = _mTokenRate;
        tokenOutRate = _tokenOutRate;
    }

    function setOracle(MockOracle oracle_) external {
        oracle = oracle_;
    }

    function redeemInstant(
        address tokenOut,
        uint256 amountMTokenIn,
        uint256 /* minReceiveAmount */
    ) external {
        require(instantEnabled, "Instant redemption disabled");

        // Transfer mToken from caller and burn
        IERC20(address(mToken)).transferFrom(
            msg.sender,
            address(this),
            amountMTokenIn
        );
        mToken.burn(address(this), amountMTokenIn);

        // Mint baseAsset directly to the caller (simulates instant redemption)
        uint256 baseAssetAmount = amountMTokenIn * getMTokenRate() / 10**(36 - IERC20Metadata(baseAsset).decimals());
        baseAsset.mint(msg.sender, baseAssetAmount); // simple 18→6 decimal conversion
    }

    function redeemRequest(
        address tokenOut,
        uint256 amountMTokenIn
    ) external returns (uint256) {
        // Transfer mToken from caller
        IERC20(address(mToken)).transferFrom(
            msg.sender,
            address(this),
            amountMTokenIn
        );

        uint256 requestId = nextRequestId++;
        _requests[requestId] = Request(
            msg.sender,
            tokenOut,
            RequestStatus.Pending,
            amountMTokenIn,
            getMTokenRate(),
            tokenOutRate
        );
        return requestId;
    }

    function redeemRequests(
        uint256 requestId
    ) external view returns (Request memory) {
        return _requests[requestId];
    }

    // Admin function to fulfill a redeem request — sends baseAsset to the original sender (proxy)
    function fulfillRequest(
        uint256 requestId
    ) public {
        Request storage req = _requests[requestId];
        require(req.status == RequestStatus.Pending, "Not pending");
        req.status = RequestStatus.Processed;

        uint256 baseAssetAmount = req.amountMToken * req.mTokenRate / 10**(36 - IERC20Metadata(baseAsset).decimals());

        // Mint baseAsset and send to the original sender (the proxy contract)
        baseAsset.mint(req.sender, baseAssetAmount);
    }

    function approveRequest (uint256 requestId, uint256 newMTokenRate) external {
        fulfillRequest(requestId);
    }

    function getMTokenRate () internal view returns (uint256) {
        if (address(oracle) != address(0)) {
            (, int256 rate, , , ) = oracle.latestRoundData();
            return uint256(rate) * 1e10;
        }
        return mTokenRate;
    }
}
