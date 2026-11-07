// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {PriceFeedType} from "@gearbox-protocol/sdk-gov/contracts/PriceFeedType.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IACL} from "@gearbox-protocol/permissionless/contracts/interfaces/IACL.sol";

import {IPriceFeed, IUpdatablePriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";
import {PriceFeedParams} from "@gearbox-protocol/oracles-v3/contracts/oracles/PriceFeedParams.sol";
import {ZeroPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/ZeroPriceFeed.sol";
import {CompositePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/CompositePriceFeed.sol";
import {BoundedPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/BoundedPriceFeed.sol";
import {RedstonePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/RedstonePriceFeed.sol";
import {ERC4626PriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/erc4626/ERC4626PriceFeed.sol";
import {WstETHPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/lido/WstETHPriceFeed.sol";
import {PendleTWAPPTPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/pendle/PendleTWAPPTPriceFeed.sol";
import {CurveStableLPPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/curve/CurveStableLPPriceFeed.sol";
import {CurveCryptoLPPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/curve/CurveCryptoLPPriceFeed.sol";

interface IOldPriceOracle {
    function priceFeedParams(address token)
        external
        view
        returns (address priceFeed, uint32 stalenessPeriod, bool skipCheck, uint8 decimals, bool trusted);

    function acl() external view returns (address acl);

    function setReservePriceFeedStatus(address token, bool active) external;
}

interface IOldPriceFeed {
    function priceFeedType() external view returns (PriceFeedType);
}

contract PriceFeedCloner is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    address configurator;

    address public zeroPriceFeed;
    mapping(address => address) mainPriceFeeds;
    mapping(address => address) reservePriceFeeds;

    mapping(address => uint32) stalenessPeriods;

    mapping(address => address) oldToNewPriceFeed;

    mapping(address => EnumerableSet.AddressSet) internal _updatablePriceFeeds;

    constructor(address _configurator) {
        configurator = _configurator;
    }

    function deployZeroPriceFeed() external {
        if (zeroPriceFeed == address(0)) {
            vm.prank(configurator);
            zeroPriceFeed = address(new ZeroPriceFeed());
        }
    }

    function _migrateFromOld(address token, address oldPriceFeed, uint32 oldStalenessPeriod)
        internal
        returns (address newPriceFeed)
    {
        if (oldPriceFeed == address(0)) {
            return address(0);
        }

        if (oldToNewPriceFeed[oldPriceFeed] != address(0)) {
            return oldToNewPriceFeed[oldPriceFeed];
        }

        PriceFeedType pfType;

        try IOldPriceFeed(oldPriceFeed).priceFeedType() returns (PriceFeedType _pfType) {
            pfType = _pfType;
        } catch {
            pfType = PriceFeedType.CHAINLINK_ORACLE;
        }

        /// CHAINLINK
        if (pfType == PriceFeedType.CHAINLINK_ORACLE) {
            newPriceFeed = oldPriceFeed;
        }
        /// ZERO ORACLE
        else if (pfType == PriceFeedType.ZERO_ORACLE) {
            if (zeroPriceFeed == address(0)) {
                vm.prank(configurator);
                zeroPriceFeed = address(new ZeroPriceFeed());
            }

            newPriceFeed = zeroPriceFeed;
        }
        /// COMPOSITE ORACLE
        else if (pfType == PriceFeedType.COMPOSITE_ORACLE) {
            PriceFeedParams[2] memory pfParams;

            pfParams[0].stalenessPeriod = CompositePriceFeed(oldPriceFeed).stalenessPeriod0();
            pfParams[0].priceFeed =
                _migrateFromOld(token, CompositePriceFeed(oldPriceFeed).priceFeed0(), pfParams[0].stalenessPeriod);

            pfParams[1].stalenessPeriod = CompositePriceFeed(oldPriceFeed).stalenessPeriod1();
            pfParams[1].priceFeed =
                _migrateFromOld(token, CompositePriceFeed(oldPriceFeed).priceFeed1(), pfParams[1].stalenessPeriod);

            string memory descriptor = string(
                abi.encodePacked(
                    IPriceFeed(pfParams[0].priceFeed).description(),
                    " * ",
                    IPriceFeed(pfParams[1].priceFeed).description()
                )
            );

            vm.prank(configurator);
            newPriceFeed = address(new CompositePriceFeed(pfParams, descriptor));
        }
        /// BOUNDED ORACLE
        else if (pfType == PriceFeedType.BOUNDED_ORACLE) {
            uint32 stalenessPeriod = BoundedPriceFeed(oldPriceFeed).stalenessPeriod();
            address underlyingFeed = _migrateFromOld(token, BoundedPriceFeed(oldPriceFeed).priceFeed(), stalenessPeriod);
            int256 upperBound = BoundedPriceFeed(oldPriceFeed).upperBound();
            string memory descriptor = string(abi.encodePacked(IPriceFeed(underlyingFeed).description()));

            vm.prank(configurator);
            newPriceFeed = address(new BoundedPriceFeed(underlyingFeed, stalenessPeriod, upperBound, descriptor));
        }
        /// REDSTONE ORACLE
        else if (pfType == PriceFeedType.REDSTONE_ORACLE) {
            address redstoneToken = RedstonePriceFeed(oldPriceFeed).token();
            bytes32 dataFeedId = RedstonePriceFeed(oldPriceFeed).dataFeedId();
            address[10] memory signers;
            signers[0] = RedstonePriceFeed(oldPriceFeed).signerAddress0();
            signers[1] = RedstonePriceFeed(oldPriceFeed).signerAddress1();
            signers[2] = RedstonePriceFeed(oldPriceFeed).signerAddress2();
            signers[3] = RedstonePriceFeed(oldPriceFeed).signerAddress3();
            signers[4] = RedstonePriceFeed(oldPriceFeed).signerAddress4();
            signers[5] = RedstonePriceFeed(oldPriceFeed).signerAddress5();
            signers[6] = RedstonePriceFeed(oldPriceFeed).signerAddress6();
            signers[7] = RedstonePriceFeed(oldPriceFeed).signerAddress7();
            signers[8] = RedstonePriceFeed(oldPriceFeed).signerAddress8();
            signers[9] = RedstonePriceFeed(oldPriceFeed).signerAddress9();
            uint8 signersThreshold = RedstonePriceFeed(oldPriceFeed).getUniqueSignersThreshold();
            string memory descriptor = string(abi.encodePacked(ERC20(token).symbol()));

            vm.prank(configurator);
            newPriceFeed = address(
                new RedstonePriceFeed(
                    redstoneToken, "redstone-primary-prod", dataFeedId, signers, signersThreshold, descriptor
                )
            );

            _updateRedstonePriceFeed(newPriceFeed);
        }
        /// ERC4626 ORACLE
        else if (pfType == PriceFeedType.ERC4626_VAULT_ORACLE) {
            uint256 lowerBound = ERC4626PriceFeed(oldPriceFeed).getLPExchangeRate();
            address vault = ERC4626PriceFeed(oldPriceFeed).lpContract();
            uint32 stalenessPeriod = ERC4626PriceFeed(oldPriceFeed).stalenessPeriod();
            address underlyingFeed = _migrateFromOld(token, ERC4626PriceFeed(oldPriceFeed).priceFeed(), stalenessPeriod);

            vm.prank(configurator);
            newPriceFeed =
                address(new ERC4626PriceFeed(configurator, lowerBound, vault, underlyingFeed, stalenessPeriod));
        }
        /// WSTETH ORACLE
        else if (pfType == PriceFeedType.WSTETH_ORACLE) {
            uint256 lowerBound = WstETHPriceFeed(oldPriceFeed).getLPExchangeRate();
            address wstETH = WstETHPriceFeed(oldPriceFeed).lpContract();
            uint32 stalenessPeriod = WstETHPriceFeed(oldPriceFeed).stalenessPeriod();
            address underlyingFeed = _migrateFromOld(token, WstETHPriceFeed(oldPriceFeed).priceFeed(), stalenessPeriod);

            vm.prank(configurator);
            newPriceFeed =
                address(new WstETHPriceFeed(configurator, lowerBound, wstETH, underlyingFeed, stalenessPeriod));
        }
        /// PENDLE PT TWAP
        else if (pfType == PriceFeedType.PENDLE_PT_TWAP_ORACLE) {
            address market = PendleTWAPPTPriceFeed(oldPriceFeed).market();
            uint32 stalenessPeriod = PendleTWAPPTPriceFeed(oldPriceFeed).stalenessPeriod();
            address underlyingPriceFeed =
                _migrateFromOld(token, PendleTWAPPTPriceFeed(oldPriceFeed).priceFeed(), stalenessPeriod);
            uint32 twapWindow = PendleTWAPPTPriceFeed(oldPriceFeed).twapWindow();

            vm.prank(configurator);
            newPriceFeed =
                address(new PendleTWAPPTPriceFeed(market, underlyingPriceFeed, stalenessPeriod, twapWindow, false));
        }
        /// CURVE STABLE LP PRICE FEED
        else if (_isCurvePriceFeedType(pfType)) {
            uint256 lowerBound = CurveStableLPPriceFeed(oldPriceFeed).getLPExchangeRate();
            address lpToken = CurveStableLPPriceFeed(oldPriceFeed).lpToken();
            address pool = CurveStableLPPriceFeed(oldPriceFeed).lpContract();

            PriceFeedParams[4] memory pfParams;

            pfParams[0].stalenessPeriod = CurveStableLPPriceFeed(oldPriceFeed).stalenessPeriod0();
            pfParams[0].priceFeed =
                _migrateFromOld(token, CurveStableLPPriceFeed(oldPriceFeed).priceFeed0(), pfParams[0].stalenessPeriod);

            pfParams[1].stalenessPeriod = CurveStableLPPriceFeed(oldPriceFeed).stalenessPeriod1();
            pfParams[1].priceFeed =
                _migrateFromOld(token, CurveStableLPPriceFeed(oldPriceFeed).priceFeed1(), pfParams[1].stalenessPeriod);

            pfParams[2].stalenessPeriod = CurveStableLPPriceFeed(oldPriceFeed).stalenessPeriod2();
            pfParams[2].priceFeed =
                _migrateFromOld(token, CurveStableLPPriceFeed(oldPriceFeed).priceFeed2(), pfParams[2].stalenessPeriod);

            pfParams[3].stalenessPeriod = CurveStableLPPriceFeed(oldPriceFeed).stalenessPeriod3();
            pfParams[3].priceFeed =
                _migrateFromOld(token, CurveStableLPPriceFeed(oldPriceFeed).priceFeed3(), pfParams[3].stalenessPeriod);

            vm.prank(configurator);
            newPriceFeed = address(new CurveStableLPPriceFeed(configurator, lowerBound, lpToken, pool, pfParams));
        }
        /// CURVE CRYPTO LP PRICE FEED
        else if (pfType == PriceFeedType.CURVE_CRYPTO_ORACLE) {
            uint256 lowerBound = CurveCryptoLPPriceFeed(oldPriceFeed).getLPExchangeRate();
            address lpToken = CurveCryptoLPPriceFeed(oldPriceFeed).lpToken();
            address pool = CurveCryptoLPPriceFeed(oldPriceFeed).lpContract();

            PriceFeedParams[3] memory pfParams;

            pfParams[0].stalenessPeriod = CurveCryptoLPPriceFeed(oldPriceFeed).stalenessPeriod0();
            pfParams[0].priceFeed =
                _migrateFromOld(token, CurveCryptoLPPriceFeed(oldPriceFeed).priceFeed0(), pfParams[0].stalenessPeriod);

            pfParams[1].stalenessPeriod = CurveCryptoLPPriceFeed(oldPriceFeed).stalenessPeriod1();
            pfParams[1].priceFeed =
                _migrateFromOld(token, CurveCryptoLPPriceFeed(oldPriceFeed).priceFeed1(), pfParams[1].stalenessPeriod);

            pfParams[2].stalenessPeriod = CurveCryptoLPPriceFeed(oldPriceFeed).stalenessPeriod2();
            pfParams[2].priceFeed =
                _migrateFromOld(token, CurveCryptoLPPriceFeed(oldPriceFeed).priceFeed2(), pfParams[2].stalenessPeriod);

            vm.prank(configurator);
            newPriceFeed = address(new CurveCryptoLPPriceFeed(configurator, lowerBound, lpToken, pool, pfParams));
        }

        oldToNewPriceFeed[oldPriceFeed] = newPriceFeed;
        stalenessPeriods[newPriceFeed] = oldStalenessPeriod;
    }

    function migratePriceFeed(address oldPriceOracle, address token, bool reserve)
        external
        returns (address newPriceFeed, uint32 stalenessPeriod)
    {
        if (reserve) {
            if (reservePriceFeeds[token] != address(0)) {
                return (reservePriceFeeds[token], stalenessPeriods[reservePriceFeeds[token]]);
            }
        } else {
            if (mainPriceFeeds[token] != address(0)) {
                return (mainPriceFeeds[token], stalenessPeriods[mainPriceFeeds[token]]);
            }
        }

        address oldPriceFeed;
        {
            address acl = IOldPriceOracle(oldPriceOracle).acl();
            address poConfigurator = Ownable(acl).owner();

            if (reserve) {
                vm.prank(poConfigurator);
                try IOldPriceOracle(oldPriceOracle).setReservePriceFeedStatus(token, true) {
                    (oldPriceFeed, stalenessPeriod,,,) = IOldPriceOracle(oldPriceOracle).priceFeedParams(token);
                } catch {
                    return (address(0), 0);
                }
            } else {
                vm.prank(poConfigurator);
                try IOldPriceOracle(oldPriceOracle).setReservePriceFeedStatus(token, false) {} catch {}
                (oldPriceFeed, stalenessPeriod,,,) = IOldPriceOracle(oldPriceOracle).priceFeedParams(token);
            }
        }

        newPriceFeed = _migrateFromOld(token, oldPriceFeed, stalenessPeriod);

        if (reserve) {
            reservePriceFeeds[token] = newPriceFeed;
        } else {
            mainPriceFeeds[token] = newPriceFeed;
        }
    }

    function _isCurvePriceFeedType(PriceFeedType pft) internal pure returns (bool) {
        return pft == PriceFeedType.CURVE_2LP_ORACLE || pft == PriceFeedType.CURVE_3LP_ORACLE
            || pft == PriceFeedType.CURVE_4LP_ORACLE;
    }

    function _updateRedstonePriceFeed(address priceFeed) internal {
        uint256 initialTS = block.timestamp;

        bytes32 dataFeedId = RedstonePriceFeed(priceFeed).dataFeedId();
        uint8 signersThreshold = RedstonePriceFeed(priceFeed).getUniqueSignersThreshold();

        bytes memory payload = _getRedstonePayload(bytes32ToString((dataFeedId)), Strings.toString(signersThreshold));

        if (payload.length == 0) return;

        (uint256 expectedPayloadTimestamp,) = abi.decode(payload, (uint256, bytes));

        if (expectedPayloadTimestamp > block.timestamp) {
            vm.warp(expectedPayloadTimestamp);
        }

        try RedstonePriceFeed(priceFeed).updatePrice(payload) {} catch {}

        vm.warp(initialTS);
    }

    function _getRedstonePayload(string memory dataFeedId, string memory signersThreshold)
        internal
        returns (bytes memory)
    {
        string[] memory args = new string[](6);
        args[0] = "npx";
        args[1] = "ts-node";
        args[2] = "./script/redstone.ts";
        args[3] = "redstone-primary-prod";
        args[4] = dataFeedId;
        args[5] = signersThreshold;

        try vm.ffi(args) returns (bytes memory response) {
            return response;
        } catch {}

        return "";
    }

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
