// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol"; 
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./SHOtoken.sol"; //Mintable Token that is being sold

contract Presale is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    struct UserInfo{
        address user;
        uint amount; // amount of USDT deposited by user
               
    }

    mapping(address => UserInfo) public sales;

    address public admin;
    uint public end;
    uint public duration;  //duration of sales in seconds  
    uint public availableTokens; //availableTokens for sales
    Token public token; //shoToken

    //======CONSTANTS======
     uint256 public price = 1* 1e16; // 0.01 USDT per SHO
     uint256 public fcfsMinCap = 50 * 1e18; // $50 Minimum deposit for FCFS
     uint256 public fcfsMaxCap = 500 * 1e18; // $500 Ma deposit for FCFS
     uint256 public minPurchase = 100 * 1e18; // 100 USDT Minimum Purchase
     uint256 public maxPurchase = 200 * 1e18; // 200 USDT cap for each whitelisted user     
    IERC20 public USDT = IERC20(0xd9145CCE52D386f254917e481eB44e9943F39138); //Address of the ERC20 token used for purchase
    
    uint256 public firstRoundDeposits; //total amount deposited by users in Round1
    uint256 public secondRoundDeposits;  //total amount deposited by users in Round2
    
    mapping(address => bool) public whitelisted; // True if user is whitelisted

    constructor(
         address tokenAddress,
         uint _duration,        
         uint _availableTokens){
             token = Token(tokenAddress);
             require(_duration > 1500, "Sales Should Be Open for Atleast 25mins");
             require(_availableTokens > 0 && _availableTokens <= token.maxTotalSupply());            

             admin = msg.sender;
             duration = _duration;            
             availableTokens = _availableTokens;
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

    //Start IDO    
    function start() external onlyAdmin() idoNotActive(){
        end = block.timestamp + duration;
    }    
    
    //Deposits from Whitelistd Addresses capped  at maxPurchase
    function deposit(uint USDTAmount) external idoActive(){
        UserInfo storage firstRoundPurchase = sales[msg.sender];
        require( maxPurchase >= firstRoundPurchase.amount.add(USDTAmount), "Whilisted address is capped at $200");
        firstRoundPurchase.amount = firstRoundPurchase.amount.add(USDTAmount);

        require(USDTAmount >= minPurchase && USDTAmount <= maxPurchase, "Min $100, Max $200");
        uint tokenAmount = USDTAmount.div(price);
        require(whitelisted[msg.sender] == true, "Sorry! Address not whitelisted.");        
        require(tokenAmount <= availableTokens,"Not Enough Token Left for sale");     
   
        firstRoundDeposits = firstRoundDeposits.add(USDTAmount);    
        
        USDT.transferFrom(msg.sender, address(this), USDTAmount);
        token.mint(address(this), tokenAmount);
        sales[msg.sender] = UserInfo( msg.sender, tokenAmount);
    }

     //FCFS deposits with Maxbuy but uncapped  
    function buy(uint USDTAmount) external idoActive(){
        UserInfo storage secondRoundPurchase = sales[msg.sender];
        secondRoundPurchase.amount = secondRoundPurchase.amount.add(USDTAmount);
        
        require(USDTAmount >= fcfsMinCap && USDTAmount <= fcfsMaxCap, "Min $50, Max $500");
        uint tokenAmount = USDTAmount.div(price);        
        require(tokenAmount <= availableTokens,"Not Enough Token Left for sale");

        secondRoundDeposits = secondRoundDeposits.add(USDTAmount);
        USDT.transferFrom(msg.sender, address(this), USDTAmount);
        token.mint(address(this), tokenAmount);
        sales[msg.sender] = UserInfo(msg.sender,tokenAmount);
    }

   //Withraws All Deposits
   function extractDeposits(uint amount) external onlyAdmin() idoEnded(){
    USDT.transfer(admin, amount);
  }

    //Get totalRaised amount
    function totalRaised() external view returns ( uint256 ) {      
        return firstRoundDeposits.add(secondRoundDeposits);
    }

    //Get Each Users Deposits firstRound
    function userfirstRoundPurchase(address _user) external view returns ( uint256 ) {
       UserInfo memory firstRoundPurchase = sales[_user];
        return (firstRoundPurchase.amount);
    }

    //Get Each Users Deposits SecondRound
    function userSecondRoundPurchase(address _user) external view returns ( uint256 ) {
       UserInfo memory secondRoundPurchase = sales[_user];
        return (secondRoundPurchase.amount);
    }


     modifier idoActive(){
    require (end > 0 && block.timestamp < end && availableTokens > 0, "ido must be active");
    _;
  }

     modifier idoNotActive(){
    require(end == 0, 'ido should not be active');
    _;
  }

     modifier idoEnded(){
    require(end > 0 && (block.timestamp >= end || availableTokens == 0),"ido must have ended");
    _;
  }

     modifier onlyAdmin(){
    require(msg.sender == admin, "only admin");
     _;
  }

}

