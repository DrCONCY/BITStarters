// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../BitStarters.sol";

contract HasBitParent is Ownable {
    event ParentUpdated(address from, address to);

    BitToken public bit;

    constructor(BitToken _bit) {
        bit = _bit;

        emit ParentUpdated(address(0), address(bit));
    }

    modifier onlyBitParent() {
        require(
            address(bit) == _msgSender(),
            "HasBitParent: caller is not the crunch token"
        );
        _;
    }

    function setCrunch(BitToken _bit) public onlyOwner {
        require(address(bit) != address(_bit), "useless to update to same bit token");

        emit ParentUpdated(address(bit), address(_bit));

        bit = _bit;
    }
}