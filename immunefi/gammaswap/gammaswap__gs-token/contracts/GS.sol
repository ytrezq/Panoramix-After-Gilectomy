// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @title GammaSwap ERC20 Token (https://www.gammaswap.com)
/// @author Daniel D. Alcarraz (https://x.com/0x_danr)
/// @notice ERC20 token used to secure the GammaSwap protocol
/// @dev Uses LayerZero V2 OFT implementation to transfer between chains
contract GS is OFT, Initializable, UUPSUpgradeable {
    uint256 constant public MAX_SUPPLY = 1_600_000_000 * (10**18);

    string private constant mName = "GammaSwap";
    string private constant mSymbol = "GS";

    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    constructor(address lzEndpoint, address owner, uint256 amount) OFT(mName, mSymbol, lzEndpoint, owner) {
        super._transferOwnership(owner);
        _mint(owner, amount);
    }

    /// @dev Returns the name of the token.
    function name() public view virtual override returns (string memory) {
        return mName;
    }

    /// @dev Returns the symbol of the token, usually a shorter version of the name.
    function symbol() public view virtual override returns (string memory) {
        return mSymbol;
    }

    /// @dev Initialize GS Token when used as a proxy contract
    function initialize(address owner, address mintTo, uint256 amount) public virtual initializer {
        require(super.owner() == address(0), "GS: INITIALIZED");
        require(mintTo != address(0), "GS: ZERO_ADDRESS");
        endpoint.setDelegate(owner);
        super._transferOwnership(owner);
        _mint(mintTo, amount);
    }

    /// @dev Returns the address of the pending owner.
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /// @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
    /// @dev Can only be called by the current owner.
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /// @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
    /// @dev Internal function without access restriction.
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /// @dev The new owner accepts the ownership transfer.
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
        _transferOwnership(sender);
    }

    function _mint(address to, uint256 amount) internal override(ERC20) {
        super._mint(to, amount);
        require(totalSupply() <= MAX_SUPPLY, "GS: MAX_SUPPLY");
    }

    function _burn(address account, uint256 amount) internal override(ERC20) {
        super._burn(account, amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
