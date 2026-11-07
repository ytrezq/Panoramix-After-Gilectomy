// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IVault.sol";
import "./interface/IERC4626.sol";

contract Reader {

  function getAllInformation(address who, address[] memory vaults, address[] memory pools)
  public view returns (uint256[] memory, uint256[] memory, uint256[] memory) {
    return (unstakedBalances(who, vaults), stakedBalances(who, pools), vaultSharePrices(vaults));
  }

  function unstakedBalances(address who, address[] memory vaults) public view returns (uint256[] memory) {
    uint256[] memory result = new uint256[](vaults.length);
    for (uint256 i = 0; i < vaults.length; i++) {
      result[i] = IERC20(vaults[i]).balanceOf(who);
    }
    return result;
  }

  function stakedBalances(address who, address[] memory pools) public view returns (uint256[] memory) {
    uint256[] memory result = new uint256[](pools.length);
    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i] == address(0)) {
        result[i] = 0; // Handle zero address case
      } else {
        result[i] = IERC20(pools[i]).balanceOf(who);
      }
    }
    return result;
  }

  function underlyingBalances(address who, address[] memory vaults) public view returns (uint256[] memory) {
    uint256[] memory result = new uint256[](vaults.length);
    for (uint256 i = 0; i < vaults.length; i++) {
      address underlying;
      try IVault(vaults[i]).underlying() returns (address _underlying) {
        underlying = _underlying;
      } catch {
        try IERC4626(vaults[i]).asset() returns (address _underlying) {
          underlying = _underlying;
        } catch {
          underlying = address(0); // Fallback to zero address if both calls fail
        }
      }
      if (underlying == address(0)) {
        result[i] = 0; // Handle zero address case
      } else {
        result[i] = IERC20(underlying).balanceOf(who);
      }
    }
    return result;
  }

  function vaultSharePrices(address[] memory vaults) public view returns (uint256[] memory) {
    uint256[] memory result = new uint256[](vaults.length);
    for (uint256 i = 0; i < vaults.length; i++) {
      try IVault(vaults[i]).getPricePerFullShare() returns (uint256 price) {
        result[i] = price;
      } catch {
        uint8 decimals = IVault(vaults[i]).decimals();
        try IERC4626(vaults[i]).convertToAssets(10 ** decimals) returns (uint256 price) {
          result[i] = price;
        } catch {
          result[i] = 0; // Fallback to zero if both calls fail
        }
      }
    }
    return result;
  }

  function underlyingBalanceWithInvestmentForHolder(address who, address[] memory vaults)
  public view returns (uint256[] memory) {
    uint256[] memory result = new uint256[](vaults.length);
    for (uint256 i = 0; i < vaults.length; i++) {
      try IVault(vaults[i]).underlyingBalanceWithInvestmentForHolder(who) returns (uint256 balance) {
        result[i] = balance;
      } catch {
        uint256 balance = IERC20(vaults[i]).balanceOf(who);
        try IERC4626(vaults[i]).convertToAssets(balance) returns (uint256 convertedBalance) {
          result[i] = convertedBalance;
        } catch {
          result[i] = 0; // Fallback to zero if both calls fail
        }
      }
    }
    return result;
  }
}