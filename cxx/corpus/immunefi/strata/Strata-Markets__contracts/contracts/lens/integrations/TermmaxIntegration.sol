pragma solidity ^0.8.22;

import { IIntegration } from "./Interfaces.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface ITermmaxGT {
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 idx) external view returns (uint256);
    function loanInfo(uint256 tokenId) external view returns (address, uint128, bytes memory);
}

contract TermmaxIntegration is IIntegration, OwnableUpgradeable {

    string constant public name = "Termmax Integration";

    ITermmaxGT public constant GT = ITermmaxGT(0x52dB35C0A4cC409DA1e409F309f3771441c02Ab1);

    ITermmaxGT[] public markets;

    event MarketsSet();

    function balanceOf(address owner) external view returns (uint256) {
        uint256 balance = 0;
        for (uint i = 0; i < markets.length; i++) {
            balance += balanceOf(markets[i], owner);
        }
        return balance;
    }

    function balanceOf(ITermmaxGT gt, address owner) public view returns (uint256) {
        uint nfts = gt.balanceOf(owner);
        uint balance = 0;
        for (uint i = 0; i < nfts; i++) {
            uint tokenId = gt.tokenOfOwnerByIndex(owner, i);
            (address _owner, uint _debtAmt, bytes memory collateralData) = gt.loanInfo(tokenId);

            uint256 collateralAmount = abi.decode(collateralData, (uint256));
            balance += collateralAmount;
        }
        return balance;
    }

    // Set new markets
    function setMarkets (ITermmaxGT[] memory arr) external onlyOwner {
        markets = arr;
        emit MarketsSet();
    }
}
