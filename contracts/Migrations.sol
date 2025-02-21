// SPDX-License-Identifier: LGPL-3.0
pragma solidity ^0.8.22;

contract Migrations {
    address public owner = msg.sender;
    uint256 public lastCompletedMigration;

    modifier restricted() {
        if (msg.sender == owner) _;
    }

    function setCompleted(uint256 completed) public restricted {
        lastCompletedMigration = completed;
    }

    function upgrade(address newAddress) public restricted {
        Migrations upgraded = Migrations(newAddress);
        upgraded.setCompleted(lastCompletedMigration);
    }
}
