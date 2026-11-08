// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { IERC20 } from "../../modules/erc20/contracts/interfaces/IERC20.sol";

import { IGlobalsLike, IMigratorLike, IRdtLike } from "../resolvers/Interfaces.sol";

contract TestBase is Test {

    uint256 precision = 1e30;
    uint256 scalar    = 100;

    address globals;

    Vm.Wallet governor         = vm.createWallet("governor");
    Vm.Wallet operationalAdmin = vm.createWallet("operationalAdmin");
    Vm.Wallet receiver         = vm.createWallet("receiver");
    Vm.Wallet sender           = vm.createWallet("sender");

    IERC20        mpl;
    IERC20        syrup;
    IMigratorLike migrator;
    IRdtLike      stsyrup;
    IRdtLike      xmpl;

    function setUp() public virtual {
        // NOTE: Mints 10_000_000 MPL to the deployer (`msg.sender`).
        vm.prank(sender.addr);
        mpl = IERC20(deployCode("./out/MapleToken.sol/MapleToken.json", abi.encode("Maple Token", "MPL", address(1))));

        globals = deployGlobals(governor.addr);

        vm.prank(governor.addr);
        IGlobalsLike(globals).setOperationalAdmin(operationalAdmin.addr);

        // NOTE: Would be replaced with precomputed address of the migrator.
        migrator = IMigratorLike(address(0x1337));

        // NOTE: There are two contracts named `MapleToken`, one of them is in the root and the other is in the `contracts` directory.
        syrup = IERC20(deploySyrup(globals, address(migrator)));

        stsyrup = IRdtLike(deployRdt(governor.addr, address(syrup), precision));
        xmpl    = IRdtLike(deployRdt(governor.addr, address(mpl), precision));

        // NOTE: Sets migrator code onto precomputed address.
        address transplant = deployMigrator(globals, address(mpl), address(syrup), scalar);
        vm.etch(address(migrator), transplant.code);
    }

    function assertBalances(
        address[6] memory accounts,
        uint256[6] memory mpls,
        uint256[6] memory xmpls,
        uint256[6] memory syrups,
        uint256[6] memory stsyrups
    )
        internal view
    {
        for (uint256 i; i < accounts.length; i++) {
            assertEq(mpl.balanceOf(address(accounts[i])),     mpls[i]);
            assertEq(xmpl.balanceOf(address(accounts[i])),    xmpls[i]);
            assertEq(syrup.balanceOf(address(accounts[i])),   syrups[i]);
            assertEq(stsyrup.balanceOf(address(accounts[i])), stsyrups[i]);
        }
    }

    function burnSyrup(address from, uint256 amount) internal {
        vm.prank(from);
        syrup.transfer(address(0), amount);
    }

    function deployGlobals(address governor_) internal returns (address globals_) {
        address implementation = deployCode("./out/MapleGlobals.sol/MapleGlobals.json");

        globals_ = deployCode("./out/NonTransparentProxy.sol/NonTransparentProxy.json", abi.encode(governor_, implementation));
    }

    function deployMigrator(address globals_, address mpl_, address syrup_, uint256 scalar_) internal returns (address migrator_) {
        migrator_ = deployCode(
            "./out/Migrator.sol/Migrator.json", abi.encode(globals_, mpl_, syrup_, scalar_)
        );
    }

    function deployRdt(address governor_, address asset_, uint256 precision_) internal returns (address rdt) {
        rdt = deployCode(
            "./out/xMPL.sol/xMPL.json", abi.encode("token", "tkn", governor_, asset_, precision_)
        );
    }

    function deploySyrup(address globals_, address migrator_) internal returns (address token) {
        token = deployCode("./out/MapleTokenProxy.sol/MapleTokenProxy.json", abi.encode(
                globals_,
                deployCode("./out/contracts/MapleToken.sol/MapleToken.json"),
                deployCode("./out/MapleTokenInitializer.sol/MapleTokenInitializer.json"),
                migrator_
            ));
    }

    function mintSyrup(address to, uint256 amount) internal {
        vm.prank(address(migrator));
        syrup.transfer(to, amount);
    }

    function signPermit(
        address asset,
        Vm.Wallet memory owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    )
        internal returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 digest = keccak256(abi.encodePacked(
            '\x19\x01',
            IERC20(asset).DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                IERC20(asset).PERMIT_TYPEHASH(),
                owner.addr,
                spender,
                value,
                nonce,
                deadline
            ))
        ));

        ( v, r, s ) = vm.sign(owner, digest);
    }

}
