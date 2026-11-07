// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TokenDistributor is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user claims tokens.
    /// @param user The user address.
    /// @param amount The amount of tokens claimed.
    event Claimed(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims tokens.
    /// @param user The user identificator.
    /// @param amount The amount of tokens claimed.
    /// @param dstAddress The destination address of the claim.
    event ClaimedWithProof(
        bytes32 indexed user,
        uint256 amount,
        address dstAddress
    );

    /// @notice Emitted when the owner withdraws tokens.
    /// @param owner The owner address.
    /// @param amount The amount of tokens withdrawn.
    event Withdrawn(address indexed owner, uint256 amount);

    /// @notice Emitted when the owner changes the vault.
    /// @param oldVault The address of old vault.
    /// @param newVault The address of new vault.
    event VaultChanged(address indexed oldVault, address indexed newVault);

    /// @notice Emitted when the owner changes the approver address.
    /// @param oldApprover The address of old approver.
    /// @param newApprover The address of new approver.
    event ApproverChanged(
        address indexed oldApprover,
        address indexed newApprover
    );

    /// @notice Emitted when the owner changes pauser.
    /// @param oldPauser The address of old vault.
    /// @param newPauser The address of new vault.
    event PauserChanged(address indexed oldPauser, address indexed newPauser);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount();
    error AlreadyClaimed();
    error InvalidMerkleProof();
    error InvalidToken();
    error InvalidMerkleRoot();
    error EmptyMerkleProof();
    error ClaimFinished();
    error ClaimNotFinished();
    error StakingNotEnabled();
    error WrongStakeAmount();
    error WrongClaimEnd();
    error Unauthorized();
    error WrongAddress();
    error ClaimWithProofNotEnabled();
    error InvalidProof();
    error OnlyRecipientCanStake();

    /*//////////////////////////////////////////////////////////////
                           CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 constant ACCOUNT_TYPE_ADDRESS = uint256(0x1);
    uint256 constant ACCOUNT_TYPE_BYTES32 = uint256(0x2);

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The merkle root hash.
    bytes32 public immutable MERKLE_ROOT;

    /// @notice The token contract.
    IERC20 public immutable TOKEN;

    /// @notice The timestamp when the claim period ends.
    uint256 public immutable CLAIM_END;

    /*//////////////////////////////////////////////////////////////
                            PUBLIC STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The vault to deposit token for staking.
    IERC4626 public vault;

    /// @notice The the address of account with pauser right
    address public pauser;

    /// @notice Mapping of claimed status. The user is eligible to do no more than one claim.
    mapping(address user => bool claimed) public hasClaimed;

    /// @notice Mapping of claimed status. The user is eligible to do no more than one claim.
    mapping(bytes32 user => bool claimed) public hasClaimedByProof;

    /// @notice The address that acts as and approved for claiming tokens to arbitrary address.
    address public approver;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Define the merkle root, base signer, token and owner.
    /// @param _merkleRoot The merkle root hash.
    /// @param _token The token address.
    /// @param _owner The owner address.
    /// @param _claimEnd The timestamp when the claim period ends.
    /// @param _vault The address of the vault to be deposit destination in case of claim and stake.
    /// @param _approver The address that acts as and approved for claiming tokens to arbitrary address.
    constructor(
        bytes32 _merkleRoot,
        address _token,
        address _owner,
        uint256 _claimEnd,
        address _vault,
        address _pauser,
        address _approver
    ) Ownable(_owner) {
        if (_token == address(0)) revert InvalidToken();
        if (_merkleRoot == bytes32(0)) revert InvalidMerkleRoot();
        if (_claimEnd <= block.timestamp) revert WrongClaimEnd();
        if (_pauser == address(0)) revert WrongAddress();

        MERKLE_ROOT = _merkleRoot;
        TOKEN = IERC20(_token);
        CLAIM_END = _claimEnd;
        vault = IERC4626(_vault);
        pauser = _pauser;
        approver = _approver;
    }

    /// MODIFIER ///
    /**
     * PAUSE
     */
    modifier onlyPauser() {
        if (pauser != _msgSender()) {
            revert Unauthorized();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// ACCESS CONTROL FUNCTIONS ///

    function changePauser(address newPauser) external onlyOwner {
        if (newPauser == address(0)) {
            revert WrongAddress();
        }
        address oldPauser = pauser;
        pauser = newPauser;
        emit PauserChanged(oldPauser, newPauser);
    }

    /**
     * Pause deposit reporting and withdrawal validation.
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * Unpause deposit reporting and withdrawal validation.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Claim tokens using a merkle proof.
    /// @param _account The account to claim tokens for.
    /// @param _amount Amount of tokens to claim.
    /// @param _merkleProof Merkle proof of claim.
    function claim(
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) external whenNotPaused nonReentrant {
        _validateClaim(_account, _amount, _merkleProof);

        // Mark as claimed and send the tokens
        hasClaimed[_account] = true;
        TOKEN.safeTransfer(_account, _amount);

        emit Claimed(_account, _amount);
    }

    /// @notice Claim tokens using a merkle proof.
    /// @param _account The account to claim tokens for.
    /// @param _amount Amount of tokens to claim.
    /// @param _merkleProof Merkle proof of claim.
    /// @param _proof The proof (signature) that _account nomivated _dstAddress to receive tokens.
    function claimWithProof(
        bytes32 _account,
        uint256 _amount,
        address _dstAddress,
        bytes32[] calldata _merkleProof,
        bytes calldata _proof
    ) external whenNotPaused nonReentrant {
        _validateClaimWithProof(
            _account,
            _amount,
            _dstAddress,
            _merkleProof,
            _proof
        );

        // Mark as claimed and send the tokens
        hasClaimedByProof[_account] = true;
        TOKEN.safeTransfer(_dstAddress, _amount);

        emit ClaimedWithProof(_account, _amount, _dstAddress);
    }

    /// @notice Claim tokens using a merkle proof and stake them with predefined vault.
    /// @param _account The account to claim tokens for.
    /// @param _amount Amount of tokens to claim.
    /// @param _merkleProof Merkle proof of claim.
    function claimAndStake(
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) external whenNotPaused nonReentrant {
        _claimAndStake(_account, _amount, _merkleProof, _amount);
    }

    /// @notice Claim tokens using a merkle proof and stake part of them with predefined vault.
    /// @param _account The account to claim tokens for.
    /// @param _amount Amount of tokens to claim.
    /// @param _merkleProof Merkle proof of claim.
    /// @param _stakeAmount Amount to stake.
    function claimAndStake(
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof,
        uint256 _stakeAmount
    ) external whenNotPaused nonReentrant {
        _claimAndStake(_account, _amount, _merkleProof, _stakeAmount);
    }

    /// @notice Claim tokens to arbitrary address using a signature and merkle proof and stake part of
    ///         them with predefined vault.
    /// @param _account The account to claim tokens for.
    /// @param _amount Amount of tokens to claim.
    /// @param _merkleProof Merkle proof of claim.
    /// @param _stakeAmount Amount to stake.
    /// @param _proof The proof (signature) that _account nomivated _dstAddress to receive tokens.
    function claimAndStakeWithProof(
        bytes32 _account,
        uint256 _amount,
        address _dstAddress,
        bytes32[] calldata _merkleProof,
        uint256 _stakeAmount,
        bytes calldata _proof
    ) external whenNotPaused nonReentrant {
        _claimAndStakeWithProof(
            _account,
            _amount,
            _dstAddress,
            _merkleProof,
            _stakeAmount,
            _proof
        );
    }

    /// @notice Withdraw tokens from the contract.
    function withdraw() external onlyOwner {
        if (block.timestamp < CLAIM_END) revert ClaimNotFinished();

        uint256 balance = TOKEN.balanceOf(address(this));
        TOKEN.safeTransfer(msg.sender, balance);

        emit Withdrawn(msg.sender, balance);
    }

    /// @notice Change Vault to stake claimed tokens.
    function changeVault(address _newVault) external onlyOwner {
        address oldVault = address(vault);
        vault = IERC4626(_newVault);
        emit VaultChanged(oldVault, _newVault);
    }

    /// @notice Change Approver to claim on an arbitrary address
    function changeApprover(address _newApprover) external onlyOwner {
        address oldApprover = address(approver);
        approver = _newApprover;
        emit ApproverChanged(oldApprover, _newApprover);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _validateClaim(
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) internal view {
        if (_amount == 0) revert InvalidAmount();
        if (hasClaimed[_account]) revert AlreadyClaimed();
        if (_merkleProof.length == 0) revert EmptyMerkleProof();
        if (block.timestamp >= CLAIM_END) revert ClaimFinished();

        // Generate the leaf
        bytes32 leaf = keccak256(
            abi.encode(_account, _amount, ACCOUNT_TYPE_ADDRESS)
        );

        // Verify the merkle proof
        if (!MerkleProof.verify(_merkleProof, MERKLE_ROOT, leaf))
            revert InvalidMerkleProof();
    }

    function _validateClaimWithProof(
        bytes32 _account,
        uint256 _amount,
        address _dstAddress,
        bytes32[] calldata _merkleProof,
        bytes calldata proof
    ) internal view {
        if (_amount == 0) revert InvalidAmount();
        if (hasClaimedByProof[_account]) revert AlreadyClaimed();
        if (_merkleProof.length == 0) revert EmptyMerkleProof();
        if (block.timestamp >= CLAIM_END) revert ClaimFinished();
        if (approver == address(0)) revert ClaimWithProofNotEnabled();

        // Generate the leaf
        bytes32 leaf = keccak256(
            abi.encode(_account, _amount, ACCOUNT_TYPE_BYTES32)
        );

        // Verify the merkle proof
        if (!MerkleProof.verify(_merkleProof, MERKLE_ROOT, leaf))
            revert InvalidMerkleProof();

        // Verify proof provided by approver
        bytes32 data = keccak256(abi.encode(_account, _amount, _dstAddress));
        (address signer, ECDSA.RecoverError err, ) = ECDSA.tryRecover(
            data,
            proof
        );
        // ignore if bad signature
        if (err != ECDSA.RecoverError.NoError) {
            revert InvalidProof();
        }
        // if signer doesn't match consider data invalid
        if (signer != approver) {
            revert InvalidProof();
        }
    }

    function _claimAndStake(
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof,
        uint256 _stakeAmount
    ) internal {
        if (_msgSender() != _account) revert OnlyRecipientCanStake();
        if (address(vault) == address(0)) revert StakingNotEnabled();
        if (_amount < _stakeAmount) revert WrongStakeAmount();
        _validateClaim(_account, _amount, _merkleProof);

        // Mark as claimed and send the tokens
        hasClaimed[_account] = true;
        if (_amount > _stakeAmount) {
            TOKEN.safeTransfer(_account, _amount - _stakeAmount);
        }
        if (_stakeAmount > 0) {
            TOKEN.safeIncreaseAllowance(address(vault), _stakeAmount);
            vault.deposit(_stakeAmount, _account);
        }

        emit Claimed(_account, _amount);
    }

    function _claimAndStakeWithProof(
        bytes32 _account,
        uint256 _amount,
        address _dstAddress,
        bytes32[] calldata _merkleProof,
        uint256 _stakeAmount,
        bytes calldata _proof
    ) internal {
        if (_msgSender() != _dstAddress) revert OnlyRecipientCanStake();
        if (address(vault) == address(0)) revert StakingNotEnabled();
        if (_amount < _stakeAmount) revert WrongStakeAmount();
        _validateClaimWithProof(
            _account,
            _amount,
            _dstAddress,
            _merkleProof,
            _proof
        );

        // Mark as claimed and send the tokens
        hasClaimedByProof[_account] = true;
        if (_amount > _stakeAmount) {
            TOKEN.safeTransfer(_dstAddress, _amount - _stakeAmount);
        }
        if (_stakeAmount > 0) {
            TOKEN.safeIncreaseAllowance(address(vault), _stakeAmount);
            vault.deposit(_stakeAmount, _dstAddress);
        }

        emit ClaimedWithProof(_account, _amount, _dstAddress);
    }
}
