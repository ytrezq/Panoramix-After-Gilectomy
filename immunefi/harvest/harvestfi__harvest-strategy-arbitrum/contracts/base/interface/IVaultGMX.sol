// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IVaultGMX {
        
    struct PendingAction {
        bool pending;
        address sender;
        address receiver;
        uint256 amountIn;
    }

    function initializeVault(
        address _storage,
        address _underlying,
        uint256 _toInvestNumerator,
        uint256 _toInvestDenominator
    ) external;

    function balanceOf(address _holder) external view returns (uint256);

    function underlyingBalanceInVault() external view returns (uint256);

    function underlyingBalanceWithInvestment() external view returns (uint256);

    function governance() external view returns (address);

    function controller() external view returns (address);

    function underlying() external view returns (address);

    function underlyingUnit() external view returns (uint);

    function strategy() external view returns (address);

    function setStrategy(address _strategy) external;

    function announceStrategyUpdate(address _strategy) external;

    function setVaultFractionToInvest(uint256 _numerator, uint256 _denominator) external;

    function deposit(uint256 _amount) external;
    function deposit(uint256 _amount, address _receiver) external;

    function depositFor(uint256 _amount, address _holder) external;

    function withdrawAll() external;

    function withdraw(uint256 _numberOfShares) external;

    function getPricePerFullShare() external view returns (uint256);

    function underlyingBalanceWithInvestmentForHolder(address _holder) view external returns (uint256);

    /**
     * The total amount available to be deposited from this vault into the strategy, while adhering to the
     * `vaultFractionToInvestNumerator` and `vaultFractionToInvestDenominator` rules
     */
    function availableToInvestOut() external view returns (uint256);

    /**
     * This should be callable only by the controller (by the hard worker) or by governance
     */
    function doHardWork() external;

    function finalizeDeposit(bool success, bytes32 key, uint256 amount) external;
    function finalizeWithdrawal(bool success, bytes32 key, uint256 amount) external;

    function pendingDeposits(bytes32 key) external view returns (PendingAction memory);
    function pendingWithdrawals(bytes32 key) external view returns (PendingAction memory);
}
