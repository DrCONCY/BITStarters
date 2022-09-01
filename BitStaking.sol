// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC677/IERC677Receiver.sol";
import "./utils/HasBitParent.sol";
import "./BitStarters.sol";

/**
 * Staking contract for the BIT token.
 * Transfer Reward Token(BIT Token)
 * To start staking, users have to approve and Deposit their tokens to receive the reward tokens 
 
 */
contract StakingRewards is HasBitParent, IERC677Receiver {
    event Withdrawed(
        address indexed to,
        uint256 reward,
        uint256 staked,
        uint256 totalAmount
    );

    event EmergencyWithdrawed(address indexed to, uint256 staked);
    event Deposited(address indexed sender, uint256 amount);
    event RewardPerMilPerDayUpdated(uint256 rewardPerMilPerDay, uint256 totalDebt);

    struct Holder {
        /** Index in `addresses`, used for faster lookup in case of a remove. */
        uint256 index;
        /** When does an holder stake for the first time (set to `block.timestamp`). */
        uint256 start;
        /** Total amount staked by the holder. */
        uint256 totalStaked;
        /** When the reward per day is updated, the reward debt is updated to ensure that the previous reward they could have got isn't lost. */
        uint256 rewardDebt;
        /** Individual stakes. */
        Stake[] stakes;
    }

    struct Stake {
        /** How much the stake is. */
        uint256 amount;
        /** Block.timestamp When does the stakes 'started' */
        uint256 start;
    }

    /** The `rewardPerMilDay` is the amount of tokens rewarded for staking 1 million tokens staked over a 1 day period. */
    uint256 public rewardPerMilPerDay;

    /** List of all currently staking addresses. Used for looping. */
    address[] public addresses;

    /** address to Holder mapping. */
    mapping(address => Holder) public holders;

    /** Currently total staked amount by everyone. This value does not include the rewards. */
    uint256 public totalStaked;


    /** Initializes the contract by specifying the parent `BIT` and the initial `rewardPerMilPerDay`. */
    constructor(BitToken bit, uint256 _rewardPerMilPerDay)
        HasBitParent(bit)
    {
        rewardPerMilPerDay = _rewardPerMilPerDay;
    }

//==============FUNCTIONS===================
   //Deposit Your Tokens for Staking //User need to approve spending
    function deposit(uint256 amount) external {
        bit.transferFrom(_msgSender(), address(this), amount);

        _deposit(_msgSender(), amount);
    }

    //Withdraw the staked tokens and the rewards.  
    //Withdrawing will withdraw everything.   
    function withdraw() external {
        _withdraw(_msgSender());
    }

//==========VIEWS================
  //Return the total stake of a holder
    function totalStakedOf(address addr) external view returns (uint256) {
        return holders[addr].totalStaked;
    }

    //Return the earned reward of the specified `addr`.    
    function totalRewardOf(address addr) public view returns (uint256) {
        Holder storage holder = holders[addr];
        return _computeRewardOf(holder);
    }

    //Return poolPower of a holder
    //poolPower is a function of the tier
    function poolPower(address addr) external view returns( uint256){      

        if ((holders[addr].totalStaked) >= 50000*1e18){
            return 10;        
        }
        else if ((holders[addr].totalStaked) < 50000*1e18 && (holders[addr].totalStaked)>= 25000*1e18 ){
            return 5;
        }
        else if ((holders[addr].totalStaked) < 25000*1e18 && (holders[addr].totalStaked)>= 10000*1e18 ){
            return 3;
        }
        else if ((holders[addr].totalStaked) < 10000*1e18 && (holders[addr].totalStaked)>= 5000*1e18 ){
            return 2;
        }
        else if ((holders[addr].totalStaked) < 50000*1e18 && (holders[addr].totalStaked)>= 1*1e18 ){
            return 1;
        }
        else {
            return 0;
        }

    }

    //Get the number of addresses currently staking/Unique Stakers     
    function stakerCount() external view returns (uint256) {
        return addresses.length;
    }

//============MUTATIVES===========

     // Update the reward per day.  
    function setRewardPerMilPerDay(uint256 to) external onlyOwner {
        require(
            rewardPerMilPerDay != to,
            "Staking: reward per day value must be different current RewardPayDay"
        );
        require(
            to <= 1000 * 1e18,
            "Staking: reward per day must be below 1000/1M token/day"
        );

        uint256 debt = _updateDebts();
        rewardPerMilPerDay = to;

        emit RewardPerMilPerDayUpdated(rewardPerMilPerDay, debt);
    }

    //Returns the current reserve for rewards = the contract balance - the total staked.    
    function reserve() public view returns (uint256) {
        uint256 balance = contractBalance();

        if (totalStaked > balance) {
            revert(
                "Staking: the balance has less BIT than the total staked"
            );
        }
        return balance - totalStaked;
    }

    //return The current staking contract's balance     
    function contractBalance() public view returns (uint256) {
        return bit.balanceOf(address(this));
    }

    //=======Internal Logics======
     /**
     * Deposit Logic
     * @dev If the depositor is not currently holding, the `Holder.start` is set and his address is added to the addresses list.
         */
    function _deposit(address from, uint256 amount) internal {
        require(amount != 0, "cannot deposit zero");

        Holder storage holder = holders[from];

        if (!_isStaking(holder)) {
            holder.start = block.timestamp;
            holder.index = addresses.length;
            addresses.push(from);
        }

        holder.totalStaked += amount;
        holder.stakes.push(Stake({amount: amount, start: block.timestamp}));

        totalStaked += amount;

        emit Deposited(from, amount);
    }

    /**
     * Withdraw Logic
     * @dev This will remove the `Holder` from the `holders` mapping and the address from the `addresses` array.
    */
    function _withdraw(address addr) internal {
        Holder storage holder = holders[addr];

        require(_isStaking(holder), "Staking: no stakes");

        uint256 reward = _computeRewardOf(holder);

        require(
            _isReserveSufficient(reward),
            "Staking: the reserve does not have enough token  for rewards"
        );

        uint256 staked = holder.totalStaked;
        uint256 total = staked + reward;
        bit.transfer(addr, total);

        totalStaked -= staked;

        _deleteAddress(holder.index);
        delete holders[addr];

        emit Withdrawed(addr, reward, staked, total);
    }

   //============LOOPINGS/ QUERIES===========
    /**
     * Get the stakes array of an holder.
     *
     * @param addr address to get the stakes array.
     * @return the holder's stakes array.
     */
    function stakesOf(address addr) external view returns (Stake[] memory) {
        return holders[addr].stakes;
    }

    /**
     * Get the stakes array length of an holder.
     *
     * @param addr address to get the stakes array length.
     * @return the length of the `stakes` array.
     */
    function stakesCountOf(address addr) external view returns (uint256) {
        return holders[addr].stakes.length;
    }

    //Test if an address is currently staking.    
    function isStaking(address addr) public view returns (bool) {
        return _isStaking(holders[addr]);
    }

    //return total the computed total reward of everyone currrently staking     
    function totalReward() public view returns (uint256 total) {
        uint256 length = addresses.length;
        for (uint256 index = 0; index < length; index++) {
            address addr = addresses[index];

            total += totalRewardOf(addr);
        }
    }

    //Sum the reward debt of everyone.
    function totalRewardDebt() external view returns (uint256 total) {
        uint256 length = addresses.length;
        for (uint256 index = 0; index < length; index++) {
            address addr = addresses[index];

            total += rewardDebtOf(addr);
        }
    }

   //return the reward debt of the holder.
    function rewardDebtOf(address addr) public view returns (uint256) {
        return holders[addr].rewardDebt;
    }

   //Check whether the reserve has enough tokens to give to everyone.    
    function isReserveSufficient() external view returns (bool) {
        return _isReserveSufficient(totalReward());
    }

   //return whether the reserve has enough tokens to give to this address.
    function isReserveSufficientFor(address addr) external view returns (bool) {
        return _isReserveSufficient(totalRewardOf(addr));
    }

    //return if the reserve is bigger or equal to the `reward` parameter.     
    function _isReserveSufficient(uint256 reward) private view returns (bool) {
        return reserve() >= reward;
    }

    //Return `true` if the holder is staking, `false` otherwise.
    function _isStaking(Holder storage holder) internal view returns (bool) {
        return holder.stakes.length != 0;
    }

    //Update the reward debt of all holders. Usually called before a `reward per day` update.
    function _updateDebts() internal returns (uint256 total) {
        uint256 length = addresses.length;
        for (uint256 index = 0; index < length; index++) {
            address addr = addresses[index];
            Holder storage holder = holders[addr];

            uint256 debt = _updateDebtsOf(holder);

            holder.rewardDebt += debt;

            total += debt;
        }
    }

    //Update the reward debt of a specified `holder`.
    function _updateDebtsOf(Holder storage holder)
        internal
        returns (uint256 total)
    {
        uint256 length = holder.stakes.length;
        for (uint256 index = 0; index < length; index++) {
            Stake storage stake = holder.stakes[index];

            total += _computeStakeReward(stake);

            stake.start = block.timestamp;
        }
    }

    //return total the total of all of the reward for all of the holders.     
    function _computeTotalReward() internal view returns (uint256 total) {
        uint256 length = addresses.length;
        for (uint256 index = 0; index < length; index++) {
            address addr = addresses[index];
            Holder storage holder = holders[addr];

            total += _computeRewardOf(holder);
        }
    }

   //return total total reward for the holder (including the debt).
    function _computeRewardOf(Holder storage holder)
        internal view returns (uint256 total)
    {
        uint256 length = holder.stakes.length;
        for (uint256 index = 0; index < length; index++) {
            Stake storage stake = holder.stakes[index];

            total += _computeStakeReward(stake);
        }

        total += holder.rewardDebt;
    }

  //Compute the reward of a single stake. (does not include the debt)   
    function _computeStakeReward(Stake storage stake)
        internal view returns (uint256)
    {
        uint256 numberOfDays = ((block.timestamp - stake.start) / 1 days);

        return (stake.amount * numberOfDays * rewardPerMilPerDay) / 1_000_000;
    }

  /** @dev Internal function called when the {IERC677-transferAndCall} is used. */
    function onTokenTransfer(
        address sender,
        uint256 value,
        bytes memory data
    ) external override onlyBitParent {
        data; /* silence unused */

        _deposit(sender, value);
    }


//============EMERGENCY========
 
   //Empty the reserve if there is a problem.
   //Send Reserve to Owner     
    function emptyReserve() external onlyOwner {
        uint256 amount = reserve();

        require(amount != 0, "Staking: reserve is empty");

        bit.transfer(owner(), amount);
    }
 
    //Withraw everyone, send reserves to owner and destroy contract
    function emergencyDestroy() external onlyOwner {
        uint256 length = addresses.length;
        for (uint256 index = 0; index < length; index++) {
            address addr = addresses[index];
            Holder storage holder = holders[addr];

            bit.transfer(addr, holder.totalStaked);
        }

        _transferRemainingAndSelfDestruct();
    }

    /**
    *This function must only be used for emergencies as it consume less gas and does not have the check for the reserve.
     * @dev This will remove the `Holder` from the `holders` mapping and the address from the `addresses` array.
     */
    function _emergencyWithdraw(address addr) internal {
        Holder storage holder = holders[addr];

        require(_isStaking(holder), "Staking: no stakes");

        uint256 staked = holder.totalStaked;
        bit.transfer(addr, staked);

        totalStaked -= staked;

        _deleteAddress(holder.index);
        delete holders[addr];

        emit EmergencyWithdrawed(addr, staked);
    }
 
    /**
     * Delete an address from the `addresses` array.
    * @dev To avoid holes, the last value will replace the deleted address.
     */
    function _deleteAddress(uint256 index) internal {
        uint256 length = addresses.length;
        require(
            length != 0,
            "Staking: cannot remove address if array length is zero"
        );

        uint256 last = length - 1;
        if (last != index) {
            address addr = addresses[last];
            addresses[index] = addr;
            holders[addr].index = index;
        }

        addresses.pop();
    }

    //Transfer the remaining tokens back to the current contract owner and then self destruct.   
    function _transferRemainingAndSelfDestruct() internal {
        uint256 remaining = contractBalance();
        if (remaining != 0) {
            bit.transfer(owner(), remaining);
        }

        selfdestruct(payable(owner()));
    }
}