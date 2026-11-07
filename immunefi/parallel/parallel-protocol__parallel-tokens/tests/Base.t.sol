// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { console2 } from "@forge-std/console2.sol";
import { Test, Vm } from "@forge-std/Test.sol";

import "contracts/libraries/Constants.sol" as ContractConstantsLib;

import "./helpers/Deploys.sol";
import "./helpers/Defaults.sol";
import "./helpers/Assertions.sol";
import "./helpers/Utils.sol";

/// @notice Base test contract with common logic needed by all tests.
abstract contract Base_Test is Test, Deploys, Assertions, Defaults, Utils {
    //----------------------------------------
    // Set-up
    //----------------------------------------
    function setUp() public virtual override {
        // Create users for testing.
        users = Users({
            admin: _createUser("Admin"),
            dao: _createUser("DAO"),
            guardian: _createUser("Guardian"),
            feesRecipient: _createUser("Fees Recipient"),
            alice: _createUser("Alice"),
            bob: _createUser("Bob"),
            hacker: _createUser("Hacker")
        });
        _deployAccessManager(users.admin.addr, users.dao.addr, users.guardian.addr);

        // Deploy EURp token contract for chain A
        aEURp = _deployTokenP("aEURp", "aEURp");
        vm.startPrank(users.admin.addr);
        accessManager.setTargetFunctionRole(address(aEURp), getGovernorTokenPSelectorAccess(), GOVERNOR_ROLE);
        accessManager.setTargetFunctionRole(address(aEURp), getMinterTokenPSelectorAccess(), MINTER_ROLE_aEURp);
        accessManager.grantRole(MINTER_ROLE_aEURp, users.admin.addr,0);


        // Deploy EURp token contract for chain B
        bEURp = _deployTokenP("bEURp", "bEURp");
        vm.startPrank(users.admin.addr);
        accessManager.setTargetFunctionRole(address(bEURp), getGovernorTokenPSelectorAccess(), GOVERNOR_ROLE);
        accessManager.setTargetFunctionRole(address(bEURp), getMinterTokenPSelectorAccess(), MINTER_ROLE_bEURp);
        accessManager.grantRole(MINTER_ROLE_bEURp, users.admin.addr,0);
        vm.stopPrank();
    }

    /// @dev Generates a user, labels its address.
    function _createUser(string memory name) internal returns (Vm.Wallet memory user) {
        user = vm.createWallet(name);
        vm.deal({ account: user.addr, newBalance: INITIAL_BALANCE });
    }

     function _signPermitData(
        uint256 privateKey,
        address spender,
        uint256 amount,
        address token
    )
        internal
        view
        returns (uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    {
        address owner = vm.addr(privateKey);
        deadline = block.timestamp + 1 days;
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: amount,
            nonce: IERC20Permit(token).nonces(owner),
            deadline: deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (v, r, s) = vm.sign(privateKey, digest);
    }
}
