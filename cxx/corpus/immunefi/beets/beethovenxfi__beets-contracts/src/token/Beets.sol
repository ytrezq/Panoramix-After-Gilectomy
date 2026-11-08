// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract Beets is ERC20, ERC20Permit, Ownable {
    uint256 public constant YEAR_IN_SECONDS = 365 days;
    // 10% per year is the hardcoded max inflation rate, as defined in BIP-77
    uint256 public constant MAX_INFLATION_PER_YEAR = 1e17;

    // The initial start timestamp is defined on deployment. This is the start time of the current year
    // for which the minting cap is calculated.
    uint256 public startTimestampCurrentYear;

    // The amount of tokens we've minted so far for the current year
    uint256 public amountMintedCurrentYear;

    // The max amount of beets that can be minted for the current year. At the start of the year, we take the current
    // total supply and calculate the max amount of beets that can be minted for the current year as 10% of the
    // current total supply.
    uint256 public maxAmountMintableCurrentYear;

    error MintAmountTooHigh(uint256 remainingMintable);
    error CurrentYearHasNotEnded();
    error CurrentYearEnded();
    error InitialSupplyIsZero();
    error InititalMintTargetIsZero();
    error OwnerIsZero();

    constructor(uint256 _initialSupply, address _initialMintTarget, address _owner)
        ERC20("Beets", "BEETS")
        ERC20Permit("Beets")
        Ownable(msg.sender)
    {
        require(_initialSupply > 0, InitialSupplyIsZero());
        require(_initialMintTarget != address(0), InititalMintTargetIsZero());
        require(_owner != address(0), OwnerIsZero());

        _mint(_initialMintTarget, _initialSupply);

        // The current year starts at the deployment timestamp
        startTimestampCurrentYear = block.timestamp;

        amountMintedCurrentYear = 0;

        maxAmountMintableCurrentYear = (totalSupply() * MAX_INFLATION_PER_YEAR) / 1 ether;

        transferOwnership(_owner);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        if (block.timestamp > getEndTimestampCurrentYear()) {
            // The current year has ended, a call to incrementYear() is required before minting more tokens
            // In the instance that several years have passed, we ensure that no tokens are minted for previous years
            revert CurrentYearEnded();
        }

        amountMintedCurrentYear += amount;

        if (amountMintedCurrentYear > maxAmountMintableCurrentYear) {
            uint256 remainingMintable = maxAmountMintableCurrentYear - (amountMintedCurrentYear - amount);

            revert MintAmountTooHigh(remainingMintable);
        }

        _mint(to, amount);
    }

    /**
     * @notice Increments the current year by one. Must be called before minting more tokens once the current year
     * has ended.
     * @dev In the instance that several years have passed, this function may need to be called multiple times.
     */
    function incrementYear() public onlyOwner {
        if (block.timestamp <= getEndTimestampCurrentYear()) {
            revert CurrentYearHasNotEnded();
        }

        // increment the current year by one
        startTimestampCurrentYear += YEAR_IN_SECONDS;

        // reset the amount minted for the current year
        amountMintedCurrentYear = 0;

        // the max amount of beets that can be minted for the current year
        maxAmountMintableCurrentYear = (totalSupply() * MAX_INFLATION_PER_YEAR) / 1 ether;
    }

    /**
     * @notice Calculates the end timestamp for the current year.
     * @return The end timestamp for the current year.
     */
    function getEndTimestampCurrentYear() public view returns (uint256) {
        return startTimestampCurrentYear + YEAR_IN_SECONDS;
    }
}
