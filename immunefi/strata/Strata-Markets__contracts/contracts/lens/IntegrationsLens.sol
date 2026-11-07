// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IIntegration } from "./integrations/Interfaces.sol";

import { PendleIntegration } from "./integrations/PendleIntegration.sol";
import { TermmaxIntegration } from "./integrations/TermmaxIntegration.sol";
import { EulerIntegration } from "./integrations/EulerIntegration.sol";

/**
 * @title Strata Integrations Contract Helper
 * @author Strata
 */
contract IntegrationsLens is OwnableUpgradeable {

    struct TIntegrationInfo {
        string name;
        address integration;
    }
    struct TIntegrationBalance {
        string name;
        address integration;
        uint256 balance;
    }

    uint public constant decimals = 18;
    uint private decimalsInternal = 18;

    address[] public integrations;

    function initialize(address owner) external initializer {
        __Ownable_init_unchained(owner);
    }

    /**
     * @notice Calculate user's Integrations balance including holdings from partner's protocols
     * @param owner The address of the account to query
     * @return The amount of Integrations owned by `owner`
     */
    function balanceOf(address owner) view external returns (uint) {
        uint balance = 0;
        for (uint i = 0; i < integrations.length; i++) {
            balance += IIntegration(integrations[i]).balanceOf(owner);
        }
        return balance;
    }

    function balanceOfDetailed(address owner) view external returns (TIntegrationBalance[] memory) {
        TIntegrationBalance[] memory balances = new TIntegrationBalance[](integrations.length);
        for (uint i = 0; i < integrations.length; i++) {
            balances[i] = TIntegrationBalance(
                IIntegration(integrations[i]).name(),
                integrations[i],
                IIntegration(integrations[i]).balanceOf(owner)
            );
        }
        return balances;
    }

    function getIntegrations () external view returns (TIntegrationInfo[] memory) {
        TIntegrationInfo[] memory result = new TIntegrationInfo[](integrations.length);
        for (uint i = 0; i < integrations.length; i++) {
            result[i] = TIntegrationInfo(
                IIntegration(integrations[i]).name(),
                integrations[i]
            );
        }
        return result;
    }

    /**
     * @notice Add partner's protocols to the contract, if they are not already added
     * @param arr The array of IIntegration instances
     */
    function addIntegrations (IIntegration[] memory arr) external onlyOwner {
        for (uint i = 0; i < arr.length; i++) {
            address integration = address(arr[i]);
            removeIntegrationInner(integration);
            integrations.push(integration);
        }
    }

    /**
     * @notice Remove partner's protocols from the contract
     * @param arr The array of IIntegration instances
     */
    function removeIntegrations (IIntegration[] memory arr) external onlyOwner {
        for (uint i = 0; i < arr.length; i++) {
            address integration = address(arr[i]);
            removeIntegrationInner(integration);
        }
    }

    function removeIntegrationInner(address integration) internal {
        uint length = integrations.length;
        for (uint i = 0; i < length; i++) {
            if (integrations[i] == integration) {
                if (i != length - 1) {
                    integrations[i] = integrations[length - 1];
                }
                integrations.pop();
                break;
            }
        }
    }
}
