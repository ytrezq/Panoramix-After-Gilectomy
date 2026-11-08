// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocUpgradable } from "../governance/MocUpgradable.sol";

/**
 * @title MocVendors
 * @notice MocVendors allows a third-party to add a markup to all operations
 *  A vendor can set a markup themselves or ask vendors guardian to do it on their behalf.
 *  Considerations:
 *  - Theres is not a markup limit or restriction
 *  - The currency that the vendor receives is always the same that is used to pay fees(AC or Fee Token)
 *  - A malicious vendor front running an operation increasing the markup is protected by a cooldown system
 */
contract MocVendors is MocUpgradable {
    // time that must elapse for a new markup to be applied
    uint128 public constant COOLDOWN = 1 hours;
    // ------- Events -------
    event VendorMarkupChanged(address indexed vendorAddress_, uint256 newMarkup_);
    // ------- Custom Errors -------
    error NotVendorsGuardian(address sender_);
    error DelegateRevoked();
    error MarkupTooHigh();

    // -----------------------------
    // ---------- Structs ----------
    // -----------------------------
    struct MarkupData {
        // previous markup percentage [PREC]
        uint64 previous; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // next markup percentage [PREC]
        uint64 next; // 0% = 0; 1% = 10 ** 16; 100% = 10 ** 18
        // markup percentage cooldown end time. After this time, new markup percentage will be applied
        uint128 cooldownEndTime;
    }

    // ------- Storage -------

    // address authorized to change a vendor's markup
    address public vendorsGuardianAddress;
    // DEPRECATED STORAGE SLOT
    mapping(address => uint256) private vendorMarkupDeprecated;
    // addition markup pct applied on each operation when operating through a vendor
    mapping(address vendor => MarkupData markupData) public vendorMarkupData;
    // true if the vendor has revoked the delegate for the vendors guardian to set the markup
    mapping(address vendor => bool delegateRevoked) public delegateRevoked;
    // max markup percentage allowed [PREC]
    uint256 public maxMarkup;

    // ------- Initializer -------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice contract initializer
     * @param vendorsGuardianAddress_ The address authorized to change a vendor's markup
     * @param governorAddress_ The address that will define when a change contract is authorized
     * @param pauserAddress_ The address that is authorized to pause this contract
     * @param maxMarkup_ Max markup percentage allowed [PREC]
     */
    function initialize(
        address vendorsGuardianAddress_,
        address governorAddress_,
        address pauserAddress_,
        uint256 maxMarkup_
    ) external initializer {
        // slither-disable-next-line missing-zero-check
        vendorsGuardianAddress = vendorsGuardianAddress_;
        maxMarkup = maxMarkup_;
        __MocUpgradable_init(governorAddress_, pauserAddress_);
    }

    // ------- Internal Functions -------

    /**
     * @notice returns markup percentage to apply.
     *  If there is a new one and cooldown time has expired, apply that one; otherwise, apply the previous one
     * @param vendorAddress_ vendor address to get markup
     * @return markup percentage to apply [PREC]
     */
    function _getVendorMarkup(address vendorAddress_) public view returns (uint64) {
        MarkupData memory _markupData = vendorMarkupData[vendorAddress_];
        if (block.timestamp >= _markupData.cooldownEndTime) {
            return _markupData.next;
        }
        return _markupData.previous;
    }

    /**
     * @notice sets a vendor markup
     * @param vendorAddress_ vendor address to change markup
     * @param newMarkup_ new markup applied to vendor [PREC]
     * @param applyInstantly_ if true, the new markup will be applied instantly; 
        if false, the new markup will be applied after the cooldown
     */
    function _setMarkup(address vendorAddress_, uint64 newMarkup_, bool applyInstantly_) internal {
        if (newMarkup_ > maxMarkup) revert MarkupTooHigh();
        // reverts if the new markup is >= 100%
        _checkLessThanOne(newMarkup_);
        // read from storage
        MarkupData memory _markupData = vendorMarkupData[vendorAddress_];

        _markupData.previous = _getVendorMarkup(vendorAddress_);
        _markupData.next = newMarkup_;
        _markupData.cooldownEndTime = applyInstantly_ ? uint128(block.timestamp) : uint128(block.timestamp) + COOLDOWN;

        // write to storage
        vendorMarkupData[vendorAddress_] = _markupData;
        emit VendorMarkupChanged(vendorAddress_, newMarkup_);
    }

    // ------- External Functions -------

    /**
     * @notice returns markup percentage to apply.
     *  If there is a new one and cooldown time has expired, apply that one; otherwise, apply the previous one
     * @param vendorAddress_ vendor address to get markup
     * @return markup percentage to apply [PREC]
     */
    function vendorMarkup(address vendorAddress_) external view returns (uint256) {
        return uint256(_getVendorMarkup(vendorAddress_));
    }

    /**
     * @notice vendor sets its own markup
     * @dev revokes the delegate for the vendors guardian to set the markup
     * @param newMarkup_ new markup applied to vendor [PREC]
     */
    function setMarkup(uint64 newMarkup_) external {
        if (!delegateRevoked[msg.sender]) delegateRevoked[msg.sender] = true;
        _setMarkup(msg.sender, newMarkup_, false);
    }

    /**
     * @notice governor or vendors guardian set a vendor markup.
     * @dev governor or vendors guardian can set a vendor markup.
     *  Changer updates are applied instantly, while vendors guardian updates use cooldown.
     *  If the vendor has already revoked the delegate for the vendors guardian, it won't be able to set a new markup.
     * @param vendorAddress_ vendor address to change markup
     * @param newMarkup_ new markup applied to vendor [PREC]
     */
    function setVendorMarkup(address vendorAddress_, uint64 newMarkup_) external {
        bool isVendorsGuardian = msg.sender == vendorsGuardianAddress;
        bool isAuthorizedChanger = governor.isAuthorizedChanger(msg.sender);
        if (!isVendorsGuardian && !isAuthorizedChanger) revert NotVendorsGuardian(msg.sender);
        if (isVendorsGuardian && delegateRevoked[vendorAddress_]) revert DelegateRevoked();
        // if called by vendors guardian, apply cooldown; if called by an authorized changer, apply instantly
        _setMarkup(vendorAddress_, newMarkup_, isAuthorizedChanger);
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @dev Sets the address which will be authorized to set a vendor markup.
     * @param vendorsGuardianAddress_ Address which will be authorized to set a vendor markup.
     */
    function setVendorsGuardianAddress(address vendorsGuardianAddress_) public onlyAuthorizedChanger {
        // slither-disable-next-line missing-zero-check
        vendorsGuardianAddress = vendorsGuardianAddress_;
    }

    /**
     * @dev Sets the max markup percentage allowed.
     * @param maxMarkup_ Max markup percentage allowed [PREC].
     */
    function setMaxMarkup(uint256 maxMarkup_) public onlyAuthorizedChanger {
        maxMarkup = maxMarkup_;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
