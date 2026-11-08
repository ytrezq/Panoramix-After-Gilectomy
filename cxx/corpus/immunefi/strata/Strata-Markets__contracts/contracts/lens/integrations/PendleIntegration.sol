pragma solidity ^0.8.22;

import { IIntegration } from "./Interfaces.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IPendleOracle {
    function getYtToAssetRate(address market, uint32 duration) external view returns (uint256);
    function getLpToAssetRate(address market, uint32 duration) external view returns (uint256);
}

contract PendleIntegration is IIntegration, OwnableUpgradeable {

    string public constant name = "Pendle Integration";

    IPendleOracle public constant ORACLE = IPendleOracle(0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2);

    struct TPendleMarket {
        IERC20 LP;
        IERC20 YT;
        IERC20 PT;
    }

    TPendleMarket[] public markets;

    event MarketsSet();

    function balanceOf(address owner) public view returns (uint256) {
        uint256 balance = 0;
        for (uint i = 0; i < markets.length; i++) {
            balance += balanceOf(markets[i], owner);
        }
        return balance;
    }

    function balanceOf(TPendleMarket memory market, address owner) public view returns (uint256) {
        uint lpBalance = market.LP.balanceOf(owner);
        uint ytBalance = market.YT.balanceOf(owner);

        uint lpPrice = ORACLE.getLpToAssetRate(address(market.LP), 10);
        uint ytPrice = ORACLE.getYtToAssetRate(address(market.LP), 10);

        return lpBalance * lpPrice / 1 ether + ytBalance * ytPrice / 1 ether;
    }


    // Set new markets
    function setMarkets (TPendleMarket[] memory arr) external onlyOwner {
        markets = arr;
        emit MarketsSet();
    }
}
