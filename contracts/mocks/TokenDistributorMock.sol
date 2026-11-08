// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../BARD/TokenDistributor.sol";

contract TokenDistributorMock is TokenDistributor {
    constructor(
        bytes32 _merkleRoot,
        address _token,
        address _owner,
        uint256 _claimEnd,
        address _vault,
        address _pauser,
        address _approver
    )
        TokenDistributor(
            _merkleRoot,
            _token,
            _owner,
            _claimEnd,
            _vault,
            _pauser,
            _approver
        )
    {}

    function removeClaim(address _account) external whenNotPaused {
        hasClaimed[_account] = false;
    }
}
