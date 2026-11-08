import {ACL_OZ_5_2_0_Lib} from "./AccessControlLib.sol";
import {ConcreteV2RolesLib as RolesLib} from "../lib/Roles.sol";
import {ConcreteStandardVaultImplStorageLib as SVLib} from "../lib/storage/ConcreteStandardVaultImplStorageLib.sol";
import {ConcreteAsyncVaultImplStorageLib as AVLib} from "../lib/storage/ConcreteAsyncVaultImplStorageLib.sol";
import {IConcreteAsyncVaultImpl} from "../interface/IConcreteAsyncVaultImpl.sol";
import {Time} from "./Time.sol";

library StateInitLib {
    function stateInitStandardVaultImpl(address allocateModuleAddr, address initialVaultManager, address sender)
        public
    {
        SVLib.ConcreteStandardVaultImplStorage storage $ = SVLib.fetch();

        $.allocateModule = allocateModuleAddr;
        $.lastManagementFeeAccrual = Time.timestamp();

        $.maxDepositAmount = type(uint256).max;
        $.minDepositAmount = 0;
        $.maxWithdrawAmount = type(uint256).max;
        $.minWithdrawAmount = 0;

        // Setup role admins
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.VAULT_MANAGER, RolesLib.VAULT_MANAGER_ADMIN);
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.HOOK_MANAGER, RolesLib.HOOK_MANAGER_ADMIN);
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.STRATEGY_MANAGER, RolesLib.STRATEGY_MANAGER_ADMIN);
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.ALLOCATOR, RolesLib.ALLOCATOR_ADMIN);

        // setup role admins of the admins
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.VAULT_MANAGER_ADMIN, RolesLib.VAULT_MANAGER_ADMIN);
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.HOOK_MANAGER_ADMIN, RolesLib.HOOK_MANAGER_ADMIN);
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.STRATEGY_MANAGER_ADMIN, RolesLib.STRATEGY_MANAGER_ADMIN);
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.ALLOCATOR_ADMIN, RolesLib.ALLOCATOR_ADMIN);

        // Grant admin roles to the initial vault manager
        ACL_OZ_5_2_0_Lib._grantRole(RolesLib.VAULT_MANAGER_ADMIN, initialVaultManager, sender);
        ACL_OZ_5_2_0_Lib._grantRole(RolesLib.HOOK_MANAGER_ADMIN, initialVaultManager, sender);
        ACL_OZ_5_2_0_Lib._grantRole(RolesLib.STRATEGY_MANAGER_ADMIN, initialVaultManager, sender);
        ACL_OZ_5_2_0_Lib._grantRole(RolesLib.ALLOCATOR_ADMIN, initialVaultManager, sender);

        // Grant manager role to the initial vault manager
        ACL_OZ_5_2_0_Lib._grantRole(RolesLib.VAULT_MANAGER, initialVaultManager, sender);
    }

    function stateInitAsyncVaultImpl(address initialVaultManager, address sender) public {
        AVLib.ConcreteAsyncVaultImplStorage storage $ = AVLib.fetch();

        // Set initial epoch to 1,
        $.isQueueActive = true;
        $.latestEpochID = 1;
        emit IConcreteAsyncVaultImpl.WithdrawalQueueInitialized($.latestEpochID);

        // setup role admins
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.WITHDRAWAL_MANAGER, RolesLib.WITHDRAWAL_MANAGER_ADMIN);
        // setup role admins of the admins
        ACL_OZ_5_2_0_Lib._setRoleAdmin(RolesLib.WITHDRAWAL_MANAGER_ADMIN, RolesLib.WITHDRAWAL_MANAGER_ADMIN);
        // Grant admin roles to the initial vault manager
        ACL_OZ_5_2_0_Lib._grantRole(RolesLib.WITHDRAWAL_MANAGER_ADMIN, initialVaultManager, sender);
    }
}
