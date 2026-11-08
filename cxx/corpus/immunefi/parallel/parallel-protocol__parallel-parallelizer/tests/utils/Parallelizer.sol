// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { IParallelizer } from "contracts/interfaces/IParallelizer.sol";
import { DiamondProxy } from "contracts/parallelizer/DiamondProxy.sol";
import "contracts/parallelizer/Storage.sol";
import { DiamondCut } from "contracts/parallelizer/facets/DiamondCut.sol";
import { DiamondEtherscan } from "contracts/parallelizer/facets/DiamondEtherscan.sol";
import { DiamondLoupe } from "contracts/parallelizer/facets/DiamondLoupe.sol";
import { Getters } from "contracts/parallelizer/facets/Getters.sol";
import { Redeemer } from "contracts/parallelizer/facets/Redeemer.sol";
import { RewardHandler } from "contracts/parallelizer/facets/RewardHandler.sol";
import { SettersGovernor } from "contracts/parallelizer/facets/SettersGovernor.sol";
import { SettersGuardian } from "contracts/parallelizer/facets/SettersGuardian.sol";
import { Swapper } from "contracts/parallelizer/facets/Swapper.sol";
import { Surplus } from "contracts/parallelizer/facets/Surplus.sol";
import "contracts/utils/Errors.sol";
import { DummyDiamondImplementation } from "scripts/generated/DummyDiamondImplementation.sol";

import "./Helper.sol";
import { console } from "@forge-std/console.sol";

abstract contract Parallelizer is Helper {
  // Diamond
  IParallelizer parallelizer;

  string[] facetNames;
  address[] facetAddressList;

  // @dev Deploys diamond and connects facets
  function deployParallelizer(address _init, bytes memory _calldata) public virtual {
    // Deploy every facet
    facetNames.push("DiamondCut");
    facetAddressList.push(address(new DiamondCut()));

    facetNames.push("DiamondEtherscan");
    facetAddressList.push(address(new DiamondEtherscan()));

    facetNames.push("DiamondLoupe");
    facetAddressList.push(address(new DiamondLoupe()));

    facetNames.push("Getters");
    facetAddressList.push(address(new Getters()));

    facetNames.push("Redeemer");
    facetAddressList.push(address(new Redeemer()));

    facetNames.push("RewardHandler");
    facetAddressList.push(address(new RewardHandler()));

    facetNames.push("SettersGovernor");
    facetAddressList.push(address(new SettersGovernor()));

    facetNames.push("SettersGuardian");
    facetAddressList.push(address(new SettersGuardian()));

    facetNames.push("Swapper");
    facetAddressList.push(address(new Swapper()));

    facetNames.push("Surplus");
    facetAddressList.push(address(new Surplus()));

    // Build appropriate payload
    uint256 n = facetNames.length;
    FacetCut[] memory cut = new FacetCut[](n);

    for (uint256 i = 0; i < n; ++i) {
      cut[i] = FacetCut({
        facetAddress: facetAddressList[i],
        action: FacetCutAction.Add,
        functionSelectors: _generateSelectors(facetNames[i])
      });
    }

    // Deploy diamond
    parallelizer = IParallelizer(address(new DiamondProxy(cut, _init, _calldata)));
  }

  // @dev Deploys diamond and connects facets
  function deployReplicaParallelizer(
    address _init,
    bytes memory _calldata
  )
    public
    virtual
    returns (IParallelizer _parallelizer)
  {
    // Build appropriate payload
    uint256 n = facetNames.length;
    FacetCut[] memory cut = new FacetCut[](n);
    for (uint256 i = 0; i < n; ++i) {
      cut[i] = FacetCut({
        facetAddress: facetAddressList[i],
        action: FacetCutAction.Add,
        functionSelectors: _generateSelectors(facetNames[i])
      });
    }

    // Deploy diamond
    _parallelizer = IParallelizer(address(new DiamondProxy(cut, _init, _calldata)));

    return _parallelizer;
  }
}
