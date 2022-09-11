// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol"; 
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract WinnerWhitelist is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    struct UserInfo{
        address user;            
    }

    mapping(address => bool) public whitelisted; // True if user is whitelisted
    mapping(address => bool) public priorityList; // True if user is in priority list

    constructor() {}

      /**
     *  @notice adds a single PriorityList to the sale
     *  @param _address: address to whitelist
     */
    function addPriorityList(address _address) external onlyOwner {
        priorityList[_address] = true;
    }

    /**
     *  @notice adds multiple PriorityList to the sale
     *  @param _addresses: dynamic array of addresses to PriorityList
     */
    function addMultiplePriorityList(address[] calldata _addresses) external onlyOwner {
        require(_addresses.length <= 100,"Please don't add more than 100 addresses at once");
        for (uint256 i = 0; i < _addresses.length; i++) {
            priorityList[_addresses[i]] = true;
        }
    }

    // Removes an address from priorityList
     //@param _address: address to remove from whitelist    
    function removePriorityList(address _address) external onlyOwner {
        priorityList[_address] = false;
    }

    /**
     *  @notice adds a single whitelist to the sale
     *  @param _address: address to whitelist
     */
    function addWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = true;
    }

    /**
     *  @notice adds multiple whitelist to the sale
     *  @param _addresses: dynamic array of addresses to whitelist
     */
    function addMultipleWhitelist(address[] calldata _addresses) external onlyOwner {
        require(_addresses.length <= 100,"Please don't add more than 100 addresses at once");
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelisted[_addresses[i]] = true;
        }
    }

    // Removes a single whitelist from the sale
     //@param _address: address to remove from whitelist    
    function removeWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = false;
    }

    //Return PriorityList/whitelist status
    function status() external view returns(string memory){
        if (priorityList[msg.sender] == true){
            return "Congratulations! You are in PriorityList";
        }
        else if (whitelisted[msg.sender] == true){
            return "Congratulations! You are Whitelisted";
        }
        else{
            return "Address Not Found";
        } 
    }


}