// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;
/*
    A Ownable standard ERC20 that has a circulation (minting) limit.
    The owner can mint an get the tokens at any moment until the circulation limit.
*/

// prettier-ignore
import {ERC20UpgradeSafe} from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
// prettier-ignore
import {OwnableUpgradeSafe} from "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
// prettier-ignore
import {SafeMath} from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

contract MocToken is ERC20UpgradeSafe, OwnableUpgradeSafe {
    using SafeMath for uint256;
    uint256 public totalCirculation;

    /**
     * @dev Initializes the contract.
     *
     * @param _name, token name.
     *
     * @param _symbol, token symbol.
     *
     * @param _totalCirculation, limit to the amount of tokens that can be minted.
     */
    constructor(string memory _name, string memory _symbol, uint256 _totalCirculation) public {
        totalCirculation = _totalCirculation;
        ERC20UpgradeSafe.__ERC20_init(_name, _symbol);
        ERC20UpgradeSafe._setupDecimals(18);
        OwnableUpgradeSafe.__Ownable_init();
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function mint(address account, uint256 amount) external onlyOwner {
        // This token can mint only into owner account
        require(account == owner(), "Only to owner account");
        require(amount.add(totalSupply()) <= totalCirculation, "Mint limit exceeded");
        _mint(account, amount);
    }
}
