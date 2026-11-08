// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

error NotRegisteredAlchemist();

error AlchemistDuplicateEntry();

error DepositCapReached();

error DepositZeroAmount();

error PositionNotFound();

error PrematureClaim();

error DepositTooLarge();

error CallerNotOwner();

error PositionNotMatured(uint256 id, uint256 maturationBlock, uint256 currentBlock);

error PositionAlreadyPoked(uint256 id);