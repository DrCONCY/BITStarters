// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PushPayment {
  address payable[] public payees;
  event TransferReceived(address _from, uint _amount);

  constructor(address payable [] memory _address)  {
      for(uint i=0; i< _address.length; i++){
          payees.push(_address[i]);
      }
  }
  receive() payable external {
      uint256 share = msg.value / payees.length;
      for(uint i=0; i< payees.length; i++){
          payees[i].transfer(share);
      }
  }
}

////_payees == Addresses ,
// payees get equal amount
// key in address before deploy
//ReentrancyGuard not needed on PushPayment because there is no withdraw function

//To deploy, add all the Airdrops winners as an array


