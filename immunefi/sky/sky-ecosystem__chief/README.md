# Chief


## Summary

This contract provides a way to elect a "chief" contract via approval voting.

Voters lock up voting tokens to give their votes weight. The voting mechanism is
[approval voting](https://en.wikipedia.org/wiki/Approval_voting).


## Approval Voting

**Approval voting** is when each voter selects which candidates they approve of,
with the top `n` "most approved" candidates being elected. Each voter can cast
up to `n + k` votes, where `k` is some non-zero positive integer. This allows
voters to move their approval from one candidate to another without needing to
first withdraw support from the candidate being replaced. Without this, moving
approval to a new candidate could result in a less-approved candidate moving
momentarily into the set of elected candidates.

In the case of `chief`, `n` is 1.

In addition, `chief` weights votes according to the quantity of a voting
token they've chosen to lock up in the `Chief` contract.

It's important to note that the voting token used in a `chief` deployment
must be specified at the time of deployment and cannot be changed afterward.


## Notice for Client Implementations

If you are writing a frontend for this smart contract, please note that the
`address[]` parameters passed to the `etch` and `vote` functions must be
_byte-ordered sets_. E.g., `[0x0, 0x1, 0x2, ...]` is valid, `[0x1, 0x0, ...]`
and `[0x0, 0x0, 0x1, ...]` are not. This ordering constraint allows the contract
to cheaply ensure voters cannot multiply their weights by listing the same
candidate on their slate multiple times.


## APIs

`Chief` provides the following public properties:

- `live`: Indicates if the system is already active or not (1 == active, 0 == inactive).
- `hat`: Contains the address of the current "chief".
- `slates`: A mapping of `bytes32` to `address` arrays. Represents sets of candidates. Weighted votes are given to slates.
- `votes`: A mapping of voter addresses to the slate they have voted for.
- `approvals`: A mapping of candidate addresses to their `uint256` weight.
- `deposits`: A mapping of voter addresses to `uint256` number of tokens locked.
- `last`: A record representing the last block when `lift` or `launch` was called.
- `gov`: `Token` used for voting.
- `maxYays`: Maximum number of candidates a slate can hold.
- `launchThreshold`: Initial amount to lock in `address(0)` for activating the `chief`.
- `liftCooldown`: Minimum number of blocks between blocks containing a `lift`.

The following events are triggered:

- `Launch()`: Fired when the `chief` is activated.
- `Lock(uint256 wad)`: Fired when someone deposits `gov` tokens.
- `Free(uint256 wad)`:  Fired when someone withdraws `gov` tokens.
- `Etch(bytes32 indexed slate, address[] yays)`: Fired when a slate is created.
- `Vote(bytes32 indexed slate)`: Fired when a slated is voted.
- `Lift(address indexed whom)`: Fired when a new `hat` is elected.

Its public functions are as follows:


### `canCall(address caller, address, bytes4) external view returns (bool ok)`

It is the function that will be used by other contracts to verify if caller can execute an action.
In this case, it will return true if the system is active and caller equals to `hat`.


### `launch()`

Launches the system when the conditions are met (`approvals` on `address(0)` are >= `launchThreshold`).


### `lock(uint256 wad)`

Transfers from the user `wad` `gov` tokens and adds `wad` weight to the candidates on the user's selected slate.


### `free(uint256 wad)`

Returns `wad` amount of `gov` tokens to the user and subtracts `wad` weight from the candidates on the user's selected slate.
Requires that there hasn't been a `launch` or `lift` call previously done in the same block.


### `etch(address[] yays) returns (bytes32 slate)`

Save a set of ordered addresses and return a unique identifier (slate) for it.


### `vote(address[] yays) returns (bytes32 slate)`

Save a set of ordered addresses as a slate, moves the voter's weight from their
current slate to the new slate, and returns the slate's identifier.


### `vote(bytes32 slate)`

Removes voter's weight from their current slate and adds it to the specified
slate.


### `lift(address whom)`

Checks the given address and promotes it as the `hat` of the `chief` if it has more weight than the current `hat`.
Requires that there hasn't been a `launch` or another `lift` call done during the previous X blocks (defined in an immutable).
