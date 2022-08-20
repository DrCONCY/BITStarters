/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//Lock up tokens for a shareholder, all tokens unlocks on the ReleaseDate

contract Timelock {
    using SafeERC20 for IERC20;

    // ERC20  Token locked in this contract
    IERC20 private immutable _token;

    // Shareholder of tokens after they are released
    address private immutable _shareholder;

    // Timestamp when token will unlock
    uint256 private immutable _releaseTime;

    constructor(
        IERC20 token_,
        address shareholder_,
        uint256 releaseTime_
    ) {
        require(releaseTime_ > block.timestamp, "Timelock Should be in Future: release time is before current time");
        _token = token_;
        _shareholder = shareholder_;
        _releaseTime = releaseTime_;
    }

    //Returns the token being held.
    function token() public view virtual returns (IERC20) {
        return _token;
    }

    //Returns the shareholder that will receive the tokens.
    function shareholder() public view virtual returns (address) {
        return _shareholder;
    }

    //Returns the Timestamp when the tokens are released
    function releaseTime() public view virtual returns (uint256) {
        return _releaseTime;
    }

    //Transfers tokens held by the Timelock to the shareholder.
    function release() public virtual {
        require(block.timestamp >= releaseTime(), "Early Withdrawal: current time is before release time");

        uint256 amount = token().balanceOf(address(this));
        require(amount > 0, "TokenTimelock: There is no token in this contract");
        //require(_shareholder == _shareholder, "Only shareholders can release their tokens");

        token().safeTransfer(shareholder(), amount);
    }
}