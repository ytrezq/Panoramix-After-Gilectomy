// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

contract SonicBeetsMigrator is ReentrancyGuard {
    IERC20 public immutable OPERABEETS;
    IERC20 public immutable SONICBEETS;
    address public immutable TREASURY;

    bool public sonicToOperaEnabled = false;
    bool public operaToSonicEnabled = false;

    address public admin;

    error UserBalanceInsufficient();
    error MigratorBalanceInsufficient();
    error MigrationDisabled();
    error NotAdmin();

    constructor(IERC20 _OPERABEETS, IERC20 _SONICBEETS, address _TREASURY) {
        OPERABEETS = _OPERABEETS;
        SONICBEETS = _SONICBEETS;
        TREASURY = _TREASURY;
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, NotAdmin());
        _;
    }

    function exchangeOperaToSonic(uint256 amount) external nonReentrant {
        require(operaToSonicEnabled, MigrationDisabled());
        require(OPERABEETS.balanceOf(msg.sender) >= amount, UserBalanceInsufficient());
        require(SONICBEETS.balanceOf(address(this)) >= amount, MigratorBalanceInsufficient());
        OPERABEETS.transferFrom(msg.sender, address(this), amount);
        SONICBEETS.transfer(msg.sender, amount);
    }

    function exchangeSonicToOpera(uint256 amount) external nonReentrant {
        require(sonicToOperaEnabled, MigrationDisabled());
        require(SONICBEETS.balanceOf(msg.sender) >= amount, UserBalanceInsufficient());
        require(OPERABEETS.balanceOf(address(this)) >= amount, MigratorBalanceInsufficient());
        SONICBEETS.transferFrom(msg.sender, address(this), amount);
        OPERABEETS.transfer(msg.sender, amount);
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
    }

    function enableOperaToSonic(bool _toggle) external onlyAdmin {
        operaToSonicEnabled = _toggle;
    }

    function enableSonicToOpera(bool _toggle) external onlyAdmin {
        sonicToOperaEnabled = _toggle;
    }

    function withdrawOperaBeets() external onlyAdmin {
        OPERABEETS.transfer(TREASURY, OPERABEETS.balanceOf(address(this)));
    }

    function withdrawSonicBeets() external onlyAdmin {
        SONICBEETS.transfer(TREASURY, SONICBEETS.balanceOf(address(this)));
    }
}
