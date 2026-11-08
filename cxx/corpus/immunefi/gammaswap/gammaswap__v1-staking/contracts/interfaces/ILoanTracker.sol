// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Interface for Loan Tracker
/// @author Simon Mall
/// @notice Reward tracker specifically for staking loans
/// @dev Need to implement `supportsInterface` function
interface ILoanTracker is IERC20, IERC165 {
    /// @dev Initializes loan tracker
    /// @param _factory address of GammaPool factory contract
    /// @param _refId reference Id for loans that can be staked
    /// @param _manager address that has admin privileges in LoanTracker
    /// @param _name ERC20 name implementation
    /// @param _symbol ERC20 symbol implementation
    /// @param _gsPool GammaPool address
    /// @param _distributor Reward distributor
    function initialize(address _factory, uint16 _refId, address _manager, string memory _name, string memory _symbol, address _gsPool, address _distributor) external;

    /// @dev Set action handlers for this contract
    /// @param _handler Address to grant handler permissions to
    /// @param _isActive Allow or disallow handler permissions to `_handler`
    function setHandler(address _handler, bool _isActive) external;

    /// @dev Update reward params for contract
    function updateRewards() external;

    /// @dev Map staked Loan Id to staker address
    /// @param _loanId Staked loan id
    /// @return Address staked this loan
    function stakedLoans(uint256 _loanId) external view returns (address);

    /// @dev Stake loan
    /// @param _loanId Loan NFT identifier
    function stake(uint256 _loanId) external;

    /// @dev Stake loan on behalf of user
    /// @param _account Owner of loan
    /// @param _loanId Loan NFT identifier
    function stakeForAccount(address _account, uint256 _loanId) external;

    /// @dev Unstake loan
    /// @param _loanId Loan NFT identifier
    function unstake(uint256 _loanId) external;

    /// @dev Unstake loan on behalf of user
    /// @param _account Owner of loan
    /// @param _loanId Loan NFT identifier
    function unstakeForAccount(address _account, uint256 _loanId) external;

    /// @return Reward tokens emission per second
    function tokensPerInterval() external view returns (uint256);

    /// @dev Claim rewards for user
    /// @param _receiver Receiver of the rewards
    function claim(address _receiver) external returns (uint256);

    /// @dev Claim rewards on behalf of user
    /// @param _account User address eligible for rewards
    /// @param _receiver Receiver of the rewards
    function claimForAccount(address _account, address _receiver) external returns (uint256);

    /// @dev Returns claimable rewards amount for the user
    /// @param _account User address for this query
    function claimable(address _account) external view returns (uint256);

    /// @param _account User account in query
    /// @return Accrued rewards for user
    function cumulativeRewards(address _account) external view returns (uint256);

    /// @dev Set through initialize function
    /// @return GS Pool this LoanTracker is for
    function gsPool() external view returns (address);

    /// @dev Set in constructor
    /// @return Address of admin contract for this LoanTracker
    function manager() external view returns (address);

    /// @dev Set through initialize function
    /// @return Address of distributor contract for this LoanTracker
    function distributor() external view returns (address);

    /// @dev Given by distributor
    /// @return Address of reward token earned from staking
    function rewardToken() external view returns (address);

    /// @dev Emitted when rewards are claimed
    /// @param _account Beneficiary user
    /// @param _amount Rewards amount claimed
    event Claim(address _account, uint256 _amount);
}
