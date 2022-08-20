/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

//Lock up tokens for a shareholder. Token unlocks linearly

contract LinearTimelock is Context {
    event EtherReleased(uint256 amount);
    event ERC20Released(address indexed token, uint256 amount);

    uint256 private _released;
    mapping(address => uint256) private _erc20Released;
    address private immutable _shareholder;
    uint64 private immutable _start;
    uint64 private immutable _duration;

    // Set the shareholder, start timestamp and vesting duration of the vesting wallet.
     
    constructor(
        address shareholderAddress,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) {
        require(shareholderAddress != address(0), "LinearTimelock: shareholder is zero address");
        _shareholder = shareholderAddress;
        _start = startTimestamp;
        _duration = durationSeconds;
    }

    //Contract should be able to receive ERC20
    receive() external payable virtual {}

    //===========GETTERS===========================

    //Getter for the shareholder address.    
    function shareholder() public view virtual returns (address) {
        return _shareholder;
    }

    //Getter for the start timestamp.     
    function start() public view virtual returns (uint256) {
        return _start;
    }

    //Getter for the vesting duration.    
    function duration() public view virtual returns (uint256) {
        return _duration;
    }

   //============FUNCTIONS================
   
    //Amount of ERC20 Tokens already released
    function released(address token) public view virtual returns (uint256) {
        return _erc20Released[token];
    } 

   //Release the tokens that have already vested.        
    function release(address token) public virtual {
        uint256 releasable = vestedAmount(token, uint64(block.timestamp)) - released(token);
        _erc20Released[token] += releasable;
        emit ERC20Released(token, releasable);
        SafeERC20.safeTransfer(IERC20(token), shareholder(), releasable);
    }   

    //Calculates the amount of tokens that has already vested.    
    function vestedAmount(address token, uint64 timestamp) public view virtual returns (uint256) {
        return _vestingSchedule(IERC20(token).balanceOf(address(this)) + released(token), timestamp);
    }

    //Virtual implementation of the vesting formula. 
    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp) internal view virtual returns (uint256) {
        if (timestamp < start()) {
            return 0;
        } else if (timestamp > start() + duration()) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - start())) / duration();
        }
    }
}