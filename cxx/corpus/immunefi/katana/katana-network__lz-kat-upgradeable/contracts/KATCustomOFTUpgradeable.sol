// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract KATCustomOFTUpgradeable is OFTUpgradeable, PausableUpgradeable {
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function initialize(string memory _name, string memory _symbol, address _delegate) public initializer {
        __Ownable_init(_delegate);
        __OFT_init(_name, _symbol, _delegate);
        __Pausable_init();
    }

    /**
     * @notice Pause the bridge functionality
     * @dev Only the owner can pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the bridge functionality
     * @dev Only the owner can unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Override _debit to add pause check
     * @param _from The address to debit tokens from
     * @param _amountLD The amount of tokens to send in local decimals
     * @param _minAmountLD The minimum amount to send in local decimals
     * @param _dstEid The destination chain ID
     * @return amountSentLD The amount sent in local decimals
     * @return amountReceivedLD The amount received in local decimals on the remote
     */
    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        virtual
        override
        whenNotPaused
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }
}
