// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";
import {IBytecodeRepository} from "@gearbox-protocol/permissionless/contracts/interfaces/IBytecodeRepository.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {ICreditFacadeV3, MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";

import {SecuritizeWallet} from "./SecuritizeWallet.sol";
import {ISecuritizeDegenNFT} from "../interfaces/ISecuritizeDegenNFT.sol";
import {ISecuritizeRWAFactory} from "../interfaces/ISecuritizeRWAFactory.sol";
import {
    AddressValidation,
    DOMAIN_RWA_UNDERLYING,
    TYPE_BYTECODE_REPOSITORY,
    TYPE_SECURITIZE_DEGEN_NFT,
    TYPE_SECURITIZE_RWA_FACTORY
} from "../libraries/AddressValidation.sol";

/// @title  Securitize RWA Factory
/// @author Gearbox Foundation
/// @notice A factory contract that allows investors to open credit accounts whitelisted to interact
///         with DSTokens by Securitize while also allowing the latter to enforce RWA compliance
contract SecuritizeRWAFactory is ISecuritizeRWAFactory, Ownable2Step {
    using AddressValidation for IAddressProvider;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ----- //
    // TYPES //
    // ----- //

    struct CreditAccountInfo {
        address wallet;
        address investor;
        bool frozen;
    }

    struct InvestorInfo {
        uint256 nonce;
        EnumerableSet.AddressSet creditAccounts;
    }

    // --------------- //
    // STATE VARIABLES //
    // --------------- //

    bytes32 public constant override contractType = TYPE_SECURITIZE_RWA_FACTORY;
    uint256 public constant override version = 3_10;

    IAddressProvider internal immutable _ADDRESS_PROVIDER;
    ISecuritizeDegenNFT internal immutable _DEGEN_NFT;

    mapping(address creditAccount => CreditAccountInfo) internal _creditAccountInfo;
    mapping(address investor => InvestorInfo) internal _investorInfo;

    /// @dev Prevents investor from spamming with too many credit accounts
    uint256 internal constant _MAX_SANE_NONCE = 255;

    // --------- //
    // MODIFIERS //
    // --------- //

    modifier nonZeroAddress(address addr) {
        _ensureAddressIsNotZero(addr);
        _;
    }

    modifier onlyKnownCreditAccounts(address creditAccount) {
        _ensureCreditAccountIsKnown(creditAccount);
        _;
    }

    // ----------- //
    // CONSTRUCTOR //
    // ----------- //

    constructor(IAddressProvider addressProvider, address securitizeAdmin) nonZeroAddress(securitizeAdmin) {
        _ADDRESS_PROVIDER = addressProvider;

        address bytecodeRepository = _ADDRESS_PROVIDER.getGlobalAddress(TYPE_BYTECODE_REPOSITORY);
        _DEGEN_NFT = ISecuritizeDegenNFT(
            IBytecodeRepository(bytecodeRepository)
                .deploy({
                    contractType: TYPE_SECURITIZE_DEGEN_NFT,
                    version: 3_10,
                    constructorParams: abi.encode(_ADDRESS_PROVIDER, this),
                    salt: bytes32(0)
                })
        );

        _transferOwnership(securitizeAdmin);
    }

    // ------- //
    // GETTERS //
    // ------- //

    function serialize() external view override returns (bytes memory) {
        return abi.encode(owner(), _DEGEN_NFT, _DEGEN_NFT.getDSTokensData());
    }

    function getDegenNFT() external view override returns (address) {
        return address(_DEGEN_NFT);
    }

    function getTokens() public view override returns (address[] memory) {
        return _DEGEN_NFT.getDSTokens();
    }

    function isCreditAccount(address creditAccount) public view override returns (bool) {
        return _creditAccountInfo[creditAccount].wallet != address(0);
    }

    function getWallet(address creditAccount)
        external
        view
        override
        onlyKnownCreditAccounts(creditAccount)
        returns (address)
    {
        return _creditAccountInfo[creditAccount].wallet;
    }

    function getInvestor(address creditAccount)
        external
        view
        override
        onlyKnownCreditAccounts(creditAccount)
        returns (address)
    {
        return _creditAccountInfo[creditAccount].investor;
    }

    function isFrozen(address creditAccount)
        external
        view
        override
        onlyKnownCreditAccounts(creditAccount)
        returns (bool)
    {
        return _creditAccountInfo[creditAccount].frozen;
    }

    function getCreditAccounts(address investor) external view override returns (address[] memory) {
        return _investorInfo[investor].creditAccounts.values();
    }

    // ------------ //
    // USER ACTIONS //
    // ------------ //

    function precomputeWalletAddress(address creditManager, address investor) public view override returns (address) {
        return Create2.computeAddress(_getSalt(investor), keccak256(_getWalletBytecode(creditManager)));
    }

    function openCreditAccount(
        address creditManager,
        MultiCall[] calldata calls,
        address[] calldata tokensToRegister,
        ISecuritizeDegenNFT.RegisterMessage[] calldata signaturesToCache
    ) external override returns (address creditAccount, address wallet) {
        if (!_ADDRESS_PROVIDER.isCreditManager(creditManager) || _getDegenNFT(creditManager) != address(_DEGEN_NFT)) {
            revert InvalidCreditManagerException(creditManager);
        }
        address underlying = ICreditManagerV3(creditManager).underlying();
        if (!_ADDRESS_PROVIDER.hasDomain(underlying, DOMAIN_RWA_UNDERLYING)) {
            revert InvalidUnderlyingTokenException(underlying);
        }

        _DEGEN_NFT.mint(precomputeWalletAddress(creditManager, msg.sender));
        wallet = Create2.deploy(0, _getSalt(msg.sender), _getWalletBytecode(creditManager));
        creditAccount = SecuritizeWallet(wallet).getCreditAccount();

        _investorInfo[msg.sender].nonce++;
        _investorInfo[msg.sender].creditAccounts.add(creditAccount);
        _creditAccountInfo[creditAccount].wallet = wallet;
        _creditAccountInfo[creditAccount].investor = msg.sender;
        emit OpenRWACreditAccount(creditAccount, wallet, msg.sender);

        if (signaturesToCache.length != 0) {
            _cacheRegisterSignatures(msg.sender, signaturesToCache);
        }
        if (tokensToRegister.length != 0) {
            _registerCreditAccount(creditManager, creditAccount, tokensToRegister);
        }
        _multicall(wallet, calls);
    }

    function multicall(
        address creditAccount,
        MultiCall[] calldata calls,
        address[] calldata tokensToRegister,
        ISecuritizeDegenNFT.RegisterMessage[] calldata signaturesToCache
    ) external override {
        CreditAccountInfo memory creditAccountInfo = _creditAccountInfo[creditAccount];
        if (msg.sender != creditAccountInfo.investor) revert CallerIsNotInvestorException(msg.sender, creditAccount);
        if (creditAccountInfo.frozen) revert FrozenCreditAccountException(creditAccount);

        if (signaturesToCache.length != 0) {
            _cacheRegisterSignatures(creditAccountInfo.investor, signaturesToCache);
        }
        if (tokensToRegister.length != 0) {
            _registerCreditAccount(_getCreditManager(creditAccount), creditAccount, tokensToRegister);
        }
        _multicall(creditAccountInfo.wallet, calls);
    }

    // ------------- //
    // ADMIN ACTIONS //
    // ------------- //

    function setCreditAccountFrozenStatus(address creditAccount, bool frozen)
        external
        override
        onlyOwner
        onlyKnownCreditAccounts(creditAccount)
    {
        _setCreditAccountFrozenStatus(creditAccount, frozen);
    }

    function setAllCreditAccountsFrozenStatus(address investor, bool frozen) external override onlyOwner {
        InvestorInfo storage investorInfo = _investorInfo[investor];
        uint256 length = investorInfo.creditAccounts.length();
        for (uint256 i = length; i != 0; --i) {
            address creditAccount = investorInfo.creditAccounts.at(i - 1);
            _setCreditAccountFrozenStatus(creditAccount, frozen);
        }
    }

    function setAllCreditAccountsFrozenStatus(address creditManager, address investor, bool frozen)
        external
        override
        onlyOwner
    {
        InvestorInfo storage investorInfo = _investorInfo[investor];
        uint256 length = investorInfo.creditAccounts.length();
        for (uint256 i = length; i != 0; --i) {
            address creditAccount = investorInfo.creditAccounts.at(i - 1);
            if (_getCreditManager(creditAccount) != creditManager) continue;
            _setCreditAccountFrozenStatus(creditAccount, frozen);
        }
    }

    /// @dev `newInvestor` is expected to be a recognized wallet in all needed registries under the same ID as
    ///      the original investor of `creditAccount`
    function transferCreditAccount(address creditAccount, address newInvestor)
        external
        override
        onlyOwner
        nonZeroAddress(newInvestor)
        onlyKnownCreditAccounts(creditAccount)
    {
        address oldInvestor = _creditAccountInfo[creditAccount].investor;
        if (newInvestor == oldInvestor) return;
        _transferCreditAccount(creditAccount, oldInvestor, newInvestor);
    }

    /// @dev `newInvestor` is expected to be a recognized wallet in all needed registries under the same ID as `investor`
    function transferAllCreditAccounts(address investor, address newInvestor)
        external
        override
        onlyOwner
        nonZeroAddress(newInvestor)
    {
        if (newInvestor == investor) return;
        InvestorInfo storage investorInfo = _investorInfo[investor];
        uint256 length = investorInfo.creditAccounts.length();
        for (uint256 i = length; i != 0; --i) {
            address creditAccount = investorInfo.creditAccounts.at(i - 1);
            _transferCreditAccount(creditAccount, investor, newInvestor);
        }
    }

    /// @dev `newInvestor` is expected to be a recognized wallet in all needed registries under the same ID as `investor`
    function transferAllCreditAccounts(address creditManager, address investor, address newInvestor)
        external
        override
        onlyOwner
        nonZeroAddress(newInvestor)
    {
        if (newInvestor == investor) return;
        InvestorInfo storage investorInfo = _investorInfo[investor];
        uint256 length = investorInfo.creditAccounts.length();
        for (uint256 i = length; i != 0; --i) {
            address creditAccount = investorInfo.creditAccounts.at(i - 1);
            if (_getCreditManager(creditAccount) != creditManager) continue;
            _transferCreditAccount(creditAccount, investor, newInvestor);
        }
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _ensureAddressIsNotZero(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddressException();
    }

    function _ensureCreditAccountIsKnown(address creditAccount) internal view {
        if (!isCreditAccount(creditAccount)) revert UnknownCreditAccountException(creditAccount);
    }

    function _getSalt(address investor) internal view returns (bytes32) {
        uint256 nonce = _investorInfo[investor].nonce;
        if (nonce > _MAX_SANE_NONCE) revert TooManyCreditAccountsException(investor);
        return keccak256(abi.encode(investor, nonce));
    }

    function _getWalletBytecode(address creditManager) internal view returns (bytes memory) {
        return abi.encodePacked(type(SecuritizeWallet).creationCode, abi.encode(address(this), creditManager));
    }

    function _getDegenNFT(address creditManager) internal view returns (address) {
        return ICreditFacadeV3(ICreditManagerV3(creditManager).creditFacade()).degenNFT();
    }

    function _getCreditManager(address creditAccount) internal view returns (address) {
        return ICreditAccountV3(creditAccount).creditManager();
    }

    function _cacheRegisterSignatures(address investor, ISecuritizeDegenNFT.RegisterMessage[] calldata signatures)
        internal
    {
        ISecuritizeDegenNFT(_DEGEN_NFT).cacheRegisterSignatures(investor, signatures);
    }

    function _registerCreditAccount(address creditManager, address creditAccount, address[] calldata tokens) internal {
        uint256 length = tokens.length;
        for (uint256 i; i < length; ++i) {
            ICreditManagerV3(creditManager).getTokenMaskOrRevert(tokens[i]);
        }
        _DEGEN_NFT.registerCreditAccount(creditAccount, tokens);
    }

    function _multicall(address wallet, MultiCall[] calldata calls) internal {
        SecuritizeWallet(wallet).multicall(calls);
    }

    function _setCreditAccountFrozenStatus(address creditAccount, bool frozen) internal {
        if (_creditAccountInfo[creditAccount].frozen == frozen) return;
        _creditAccountInfo[creditAccount].frozen = frozen;
        emit SetCreditAccountFrozenStatus(creditAccount, frozen);
    }

    function _transferCreditAccount(address creditAccount, address oldInvestor, address newInvestor) internal {
        _creditAccountInfo[creditAccount].investor = newInvestor;
        emit TransferCreditAccount(creditAccount, oldInvestor, newInvestor);

        _investorInfo[oldInvestor].creditAccounts.remove(creditAccount);
        _investorInfo[newInvestor].creditAccounts.add(creditAccount);
    }
}
