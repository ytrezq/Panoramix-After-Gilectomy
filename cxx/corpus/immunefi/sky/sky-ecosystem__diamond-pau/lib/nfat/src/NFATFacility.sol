// SPDX-FileCopyrightText: © 2026 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.24;

import { ERC721 } from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

interface GemLike {
    function transferFrom(address from, address to, uint256 amount) external;
    function transfer(address to, uint256 amount) external;
}

interface IdentityNetworkLike {
    function isMember(address usr) external view returns (bool);
}

contract NFATFacility is ERC721 {

    mapping(address usr       => uint256 allowed) public wards;
    mapping(address usr       => uint256 allowed) public buds; // Operator(s)
    mapping(address usr       => uint256 allowed) public cops; // Freezers
    mapping(address depositor => uint256 amount)  public deposits;
    mapping(uint256 tokenId   => uint256 amount)  public collectable;
    address             public recipient; // Destination of funds claimed by the operator
    IdentityNetworkLike public identityNetwork;
    bool                public stopped;
    string              public baseURI;

    GemLike public immutable gem; // Underlying asset

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event AddFreezer(address indexed usr);
    event RemoveFreezer(address indexed usr);
    event Stop();
    event Start();
    event File(bytes32 indexed what, address data);
    event File(bytes32 indexed what, string data);
    event Rescue(address indexed token, address indexed to, uint256 amount);
    event RescueDeposit(address indexed depositor, address indexed to, uint256 amount);
    event RescueCollectable(uint256 indexed tokenId, address indexed to, uint256 amount);
    event Subscribe(address indexed depositor, uint256 amount, bytes data);
    event Withdraw(address indexed depositor, uint256 amount);
    event Issue(address indexed to, uint256 indexed tokenId, uint256 amount);
    event Repay(address indexed sender, uint256 indexed tokenId, uint256 amount);
    event Collect(uint256 indexed tokenId, uint256 amount);

    // --- Modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "NFATFacility/not-authorized");
        _;
    }

    modifier toll() {
        require(buds[msg.sender] == 1, "NFATFacility/not-operator");
        _;
    }

    modifier cop() {
        require(cops[msg.sender] == 1, "NFATFacility/not-freezer");
        _;
    }

    modifier notStopped() {
        require(!stopped, "NFATFacility/stopped");
        _;
    }

    // --- Constructor ---

    constructor(address gem_, string memory name_, string memory symbol_)
        ERC721(name_, symbol_)
    {
        gem = GemLike(gem_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- auth & cop Functions ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    function addFreezer(address usr) external auth {
        cops[usr] = 1;
        emit AddFreezer(usr);
    }

    function removeFreezer(address usr) external auth {
        cops[usr] = 0;
        emit RemoveFreezer(usr);
    }

    function stop() external cop {
        stopped = true;
        emit Stop();
    }

    function start() external auth {
        stopped = false;
        emit Start();
    }

    function file(bytes32 what, address data) external auth {
        if (what == "recipient") recipient = data;
        else if (what == "identityNetwork") identityNetwork = IdentityNetworkLike(data);
        else revert("NFATFacility/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, string calldata data) external auth {
        if (what == "baseURI") baseURI = data;
        else revert("NFATFacility/file-unrecognized-param");
        emit File(what, data);
    }

    // Note: In order to rescue gem balances tracked by the `deposits` or `collectable` mappings, prefer using rescueDeposit/rescueCollectable over this function
    // Note: tokens that return false instead of reverting on failure may cause a Rescue event to be emitted without an actual transfer
    function rescue(address token, address to, uint256 amount) external auth {
        GemLike(token).transfer(to, amount);
        emit Rescue(token, to, amount);
    }

    function rescueDeposit(address depositor, address to, uint256 amount) external auth {
        require(deposits[depositor] >= amount, "NFATFacility/insufficient-deposits");
        unchecked { deposits[depositor] -= amount; }
        gem.transfer(to, amount);
        emit RescueDeposit(depositor, to, amount);
    }

    function rescueCollectable(uint256 tokenId, address to, uint256 amount) external auth {
        require(collectable[tokenId] >= amount, "NFATFacility/insufficient-collectable");
        unchecked { collectable[tokenId] -= amount; }
        gem.transfer(to, amount);
        emit RescueCollectable(tokenId, to, amount);
    }

    // --- Queue Functions ---

    // Note: amount = 0 is allowed to emit updated data without depositing; data is arbitrary and intended for off-chain agreements
    // Note: subscribing does not guarantee eligibility to be issued an NFAT - issue() will revert if the subscriber is not in the identity network at issuance time
    function subscribe(uint256 amount, bytes calldata data) external notStopped {
        if (amount > 0) {
            gem.transferFrom(msg.sender, address(this), amount);
            deposits[msg.sender] += amount;
        }
        emit Subscribe(msg.sender, amount, data);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "NFATFacility/zero-amount");
        require(deposits[msg.sender] >= amount, "NFATFacility/insufficient-deposits");
        unchecked { deposits[msg.sender] -= amount; }
        gem.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    // Note: amount = 0 is allowed (mint NFAT without moving funds)
    // Note: _mint is used instead of _safeMint — `to` opted in via subscribe and is assumed to support ERC-721
    function issue(address to, uint256 tokenId, uint256 amount) external toll notStopped {
        require(tokenId != 0, "NFATFacility/token-id-zero");
        require(deposits[to] >= amount, "NFATFacility/insufficient-deposits");
        unchecked { deposits[to] -= amount; }
        _mint(to, tokenId); // identity network check in _update
        if (amount > 0) gem.transfer(recipient, amount);
        emit Issue(to, tokenId, amount);
    }

    // --- Redemption Functions ---

    // Note: the recipient of a transferred NFAT is assumed aware of current and future planned repayments, including potential front-running
    function repay(uint256 tokenId, uint256 amount) external notStopped {
        require(amount > 0, "NFATFacility/zero-amount");
        require(_ownerOf(tokenId) != address(0), "NFATFacility/invalid-token");
        gem.transferFrom(msg.sender, address(this), amount);
        collectable[tokenId] += amount;
        emit Repay(msg.sender, tokenId, amount);
    }

    // Note: only the NFAT owner can collect (token and operator approvals do not extend to this function); the owner is assumed to be able to call this function directly
    function collect(uint256 tokenId, uint256 amount) external notStopped {
        require(amount > 0, "NFATFacility/zero-amount");
        require(collectable[tokenId] >= amount, "NFATFacility/insufficient-collectable");
        require(msg.sender == _ownerOf(tokenId), "NFATFacility/not-owner");
        require(address(identityNetwork) == address(0) || identityNetwork.isMember(msg.sender), "NFATFacility/not-member");
        unchecked { collectable[tokenId] -= amount; }
        gem.transfer(msg.sender, amount);
        emit Collect(tokenId, amount);
    }

    // --- ERC-721 Overrides ---

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // Note: `to` is guaranteed non-zero (OZ reverts before _update when to == address(0), and _burn is never invoked)
    function _update(address to, uint256 tokenId, address auth_) internal override returns (address) {
        require(
            address(identityNetwork) == address(0) || identityNetwork.isMember(to),
            "NFATFacility/not-member"
        );
        return super._update(to, tokenId, auth_);
    }

}
