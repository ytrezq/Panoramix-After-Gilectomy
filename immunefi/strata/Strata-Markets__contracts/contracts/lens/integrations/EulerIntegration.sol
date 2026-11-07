pragma solidity ^0.8.22;

import { IIntegration } from "./Interfaces.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";


interface IEulerVault is IERC4626 {
    function EVC () external view returns (address);
}
interface IEVC {
    function getAccountOwner (address account) external view returns (address);
}

contract EulerIntegration is IIntegration, OwnableUpgradeable {

    string public constant name = "Euler Integration";

    struct TVault {
        IERC4626 eulerVault;
        IERC4626 strataVault;
    }

    TVault[] public vaults;

    event VaultsSet();

    function balanceOf(address owner) external view returns (uint256) {
        uint balance = 0;
        for (uint i = 0; i < vaults.length; i++) {
            balance += balanceOf(vaults[i].eulerVault, owner);
        }
        return balance;
    }

    function balanceOf(IERC4626 eulerVault, address owner) public view returns (uint256) {
        uint256 balance = 0;
        for (uint i = 0; i < 256; i++) {
            address account = address(uint160(owner) ^ uint160(i));
            uint shares = eulerVault.balanceOf(account);
            if (shares > 0) {
                balance += eulerVault.previewRedeem(shares);
            }
        }
        return balance;
    }

    // Set new vaults
    function setVaults (TVault[] memory arr) external onlyOwner {
        vaults = arr;
        emit VaultsSet();
    }
}
