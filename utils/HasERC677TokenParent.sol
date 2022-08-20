// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../ERC677/IERC677Metadata.sol";

contract HasERC677TokenParent is Ownable {
    event ParentTokenUpdated(address from, address to);

    IERC677Metadata public parentToken;

    constructor(address token) {
        _setParentToken(token);
    }

    function setBit(address token) public onlyOwner {
        _setParentToken(token);
    }

    function _setParentToken(address to) internal {
        address from = address(parentToken);

        require(from != address(to), "HasERC677TokenParent: useless to update to same BIT token");

        parentToken = IERC677Metadata(to);

        emit ParentTokenUpdated(from, to);

        /* test the token */
        parentToken.decimals();
    }

    modifier onlyParentParent() {
        require(address(parentToken) == _msgSender(), "HasERC677TokenParent: caller is not the crunch token");
        _;
    }
}