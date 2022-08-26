// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//A multivesting contract that unlockes per seconds

contract TokenVesting is Ownable {
    struct Schedule {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 cliffTime;
        uint256 endTime;
        bool isFixed;
        address asset;
    }

    // user => scheduleId => schedule
    mapping(address => mapping(uint256 => Schedule)) public schedules;
    mapping(address => uint256) public numberOfSchedules;

    mapping(address => uint256) public locked;

    event Claim(address indexed claimer, uint256 amount);
    event Vest(address indexed to, uint256 amount);
    event Cancelled(address account);

    constructor() {}

    /**
     * @notice Sets up a vesting schedule for a set user.
     * @dev adds a new Schedule to the schedules mapping.
     
     * @param amount the amount of tokens being vested for the user.
     * @param asset = address of the asset that the user is being vested
     * @param isFixed  Fixed vesting schedules can't be cancelled.
     * @param cliffWeeks the number of weeks that the cliff will be present at.
     * @param vestingWeeks the number of weeks the tokens will vest over (linearly)
     * @param startTime the timestamp for when this vesting should have started
     */
    function vest(
        address account,
        uint256 amount,
        address asset,
        bool isFixed,
        uint256 cliffWeeks,
        uint256 vestingWeeks,
        uint256 startTime
    ) public onlyOwner {
        // ensure cliff is shorter than vesting
        require(
            vestingWeeks > 0 && 
            vestingWeeks >= cliffWeeks &&
            amount > 0,
            "Vesting: invalid vesting params"
        );

        uint256 currentLocked = locked[asset];

        // require the token is present
        require(
            IERC20(asset).balanceOf(address(this)) >= currentLocked + amount,
            "Vesting: Not enough tokens"
        );

        // create the schedule
        uint256 currentNumSchedules = numberOfSchedules[account];
        schedules[account][currentNumSchedules] = Schedule(
            amount,
            0,
            startTime,
            startTime + (cliffWeeks * 1 weeks),
            startTime + (vestingWeeks * 1 weeks),
            isFixed,
            asset
        );
        numberOfSchedules[account] = currentNumSchedules + 1;
        locked[asset] = currentLocked + amount;
        emit Vest(account, amount);
    }

    /**
     * @notice Sets up vesting schedules for multiple users within 1 transaction.
     * @param accounts an array of the accounts 
     * @param amount an array of the amount of tokens being vested for each user.     
     */
    function multiVest(
        address[] calldata accounts,
        uint256[] calldata amount,
        address asset,
        bool isFixed,
        uint256 cliffWeeks,
        uint256 vestingWeeks,
        uint256 startTime
    ) external onlyOwner {
        uint256 numberOfAccounts = accounts.length;
        require(
            amount.length == numberOfAccounts,
            "Error: Array lengths differ"
        );
        for (uint256 i = 0; i < numberOfAccounts; i++) {
            vest(
                accounts[i],
                amount[i],
                asset,
                isFixed,
                cliffWeeks,
                vestingWeeks,
                startTime
            );
        }
    }

    /**
     * @notice allows users to claim vested tokens if the cliff time has passed.
     * @param scheduleNumber which schedule the user is claiming against(0,1,2...)
     */
    function claim(uint256 scheduleNumber) external {
        Schedule storage schedule = schedules[msg.sender][scheduleNumber];
        require(
            schedule.cliffTime <= block.timestamp,
            "Vesting: cliff not reached"
        );
        require(schedule.totalAmount > 0, "Vesting: not claimable");

        // Get the amount to be distributed
        uint256 amount = calcDistribution(
            schedule.totalAmount,
            block.timestamp,
            schedule.startTime,
            schedule.endTime
        );

        // Cap the amount at the total amount
        amount = amount > schedule.totalAmount ? schedule.totalAmount : amount;
        uint256 amountToTransfer = amount - schedule.claimedAmount;
        schedule.claimedAmount = amount; // set new claimed amount based off the curve
        locked[schedule.asset] = locked[schedule.asset] - amountToTransfer;
        require(IERC20(schedule.asset).transfer(msg.sender, amountToTransfer), "Vesting: transfer failed");
        emit Claim(msg.sender, amount);
    }

    /**
     * @notice Allows a vesting schedule to be cancelled.
     * @dev Any outstanding tokens are returned to the Vesting Contract
     * @param account the account of the user whose vesting schedule is being cancelled.
     */
    function rug(address account, uint256 scheduleId) external onlyOwner {
        Schedule storage schedule = schedules[account][scheduleId];
        require(!schedule.isFixed, "Vesting: Account is fixed");
        uint256 outstandingAmount = schedule.totalAmount -
            schedule.claimedAmount;
        require(outstandingAmount != 0, "Vesting: No outstanding tokens");
        schedule.totalAmount = 0;
        locked[schedule.asset] = locked[schedule.asset] - outstandingAmount;
        require(IERC20(schedule.asset).transfer(owner(), outstandingAmount), "Vesting: transfer failed");
        emit Cancelled(account);
    }

    /**
     * @return calculates the amount of tokens to distribute to an account at any instance in time, based off some
     *         total claimable amount.
     */
    function calcDistribution(
        uint256 amount,
        uint256 currentTime,
        uint256 startTime,
        uint256 endTime
    ) public pure returns (uint256) {
        // avoid uint underflow
        if (currentTime < startTime) {
            return 0;
        }

        // if endTime < startTime, this will throw. Since endTime should never be
        // less than startTime in safe operation, this is fine.
        return (amount * (currentTime - startTime)) / (endTime - startTime);
    }

    /**
     * @notice Withdraws unallocated tokens from the contract to the deployer
     * @dev blocks withdrawing locked tokens.
     */
    function withdraw(uint256 amount, address asset) external onlyOwner {
        IERC20 token = IERC20(asset);
        require(
            token.balanceOf(address(this)) - locked[asset] >= amount,
            "Vesting: Can't withdraw"
        );
        require(token.transfer(owner(), amount), "Vesting: withdraw failed");
        
    }
    /**
    //Create a view to displaytotal vested tokens
    function totalAmount()
    return [schedule.totalAmount]
    */
    
}

