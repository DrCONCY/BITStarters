//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//Vesting Schedule contract

contract shoVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint32 constant HUNDRED_PERCENT = 1e6;

    struct User {
        // for option 0 the fee may increase when claiming
        // for option 1 users, only the owner can increase their fees to 100% (useful for revoking vesting)
        uint8 option;

        uint128 allocation;
        uint128 totalUnlocked;
        uint128 totalClaimed;
        uint32 unlockedBatchesCount;
        uint32 feePercentageCurrentUnlock;
        uint32 feePercentageNextUnlock;


    }

    mapping(address => User) public users;

    IERC20 public immutable shoToken;
    uint64 public immutable startTime;
    uint32 public passedUnlocksCount;
    uint32[] public unlockPercentages;
    uint32[] public unlockPeriods;

    uint128 public globalTotalAllocation;
    address public immutable feeCollector;
    uint32 public immutable initialFeePercentage;
    uint32 public collectedUnlocksCount;
    uint128[] public extraFees;


    event Whitelist(
        address user,
        uint128 allocation,
        uint8 option
    );

    event UserElimination(
        address user,
        uint32 currentUnlock,
        uint128 unlockedTokens,
        uint32 increasedFeePercentage
    );

    event FeeCollection(
        uint32 currentUnlock,
        uint128 totalFee,
        uint128 baseFee,
        uint128 extraFee
    );

    event Claim(
        address user,
        uint32 currentUnlock,
        uint128 unlockedTokens,
        uint32 increasedFeePercentage,
        uint128 receivedTokens
    );

    event Update (
        uint32 passedUnlocksCount,
        uint128 extraFeesAdded
    );

    modifier onlyFeeCollector() {
        require(feeCollector == msg.sender, "SHO: caller is not the fee collector");
        _;
    }

    modifier onlyWhitelisted() {
        require(users[msg.sender].allocation > 0, "SHO: caller is not whitelisted");
        _;
    }

    /**
        @param _shoToken token that whitelisted users claim
        @param _unlockPercentagesDiff array of unlock percentages as differentials            
        @param _unlockPeriodsDiff array of unlock periods/TimeStamps as differentials            
        @param _initialFeePercentage initial fee in percentage 
        @param _feeCollector EOA that can collect fees
        @param _startTime when users can start claiming
     */
    constructor(
        IERC20 _shoToken,
        uint32[] memory _unlockPercentagesDiff,
        uint32[] memory _unlockPeriodsDiff,
        uint32 _initialFeePercentage,
        address _feeCollector,
        uint64 _startTime
    ) {
        require(address(_shoToken) != address(0), "SHO: sho token zero address");
        require(_unlockPercentagesDiff.length > 0, "SHO: 0 unlock percentages");
        require(_unlockPercentagesDiff.length <= 200, "SHO: too many unlock percentages");
        require(_unlockPeriodsDiff.length == _unlockPercentagesDiff.length, "SHO: different array lengths");
        require(_initialFeePercentage <= HUNDRED_PERCENT, "SHO: initial fee percentage higher than 100%");
        require(_feeCollector != address(0), "SHO: fee collector zero address");
        require(_startTime > block.timestamp, "SHO: start time must be in future");

        // build arrays of sums for easier calculations
        uint32[] memory _unlockPercentages = _buildArraySum(_unlockPercentagesDiff);
        uint32[] memory _unlockPeriods = _buildArraySum(_unlockPeriodsDiff);
        require(_unlockPercentages[_unlockPercentages.length - 1] == HUNDRED_PERCENT, "SHO: invalid unlock percentages");

        shoToken = _shoToken;
        unlockPercentages = _unlockPercentages;
        unlockPeriods = _unlockPeriods;
        initialFeePercentage = _initialFeePercentage;
        feeCollector = _feeCollector;
        startTime = _startTime;
        extraFees = new uint128[](_unlockPercentagesDiff.length);
    }

    /** 
        Whitelisting shall be allowed only until the SHO token is received for security reasons.
        @param userAddresses addresses to whitelist
        @param allocations users total allocation
    */
    function whitelistUsers(
        address[] calldata userAddresses,
        uint128[] calldata allocations,
        uint8[] calldata options
    ) external onlyOwner {        
        require(userAddresses.length != 0, "SHO: zero length array");
        require(userAddresses.length == allocations.length, "SHO: different array lengths");
        require(userAddresses.length == options.length, "SHO: different array lengths");

        uint128 _globalTotalAllocation;
        for (uint256 i = 0; i < userAddresses.length; i++) {
            User storage user = users[userAddresses[i]];
            require(user.allocation == 0, "SHO: some users are already whitelisted");
            require(options[i] < 2, "SHO: invalid user option");
            user.option = options[i];
            user.allocation = allocations[i];
            user.feePercentageCurrentUnlock = initialFeePercentage;
            user.feePercentageNextUnlock = initialFeePercentage;
        
            _globalTotalAllocation += allocations[i];

            emit Whitelist(
                userAddresses[i],
                allocations[i],
                options[i]
            );
        }
        globalTotalAllocation = _globalTotalAllocation;
    }

    /**
        Increases an option 1 user's next unlock fee to 100%.
        @param userAddresses whitelisted user addresses to eliminate
     */
    function eliminateOption1Users(address[] calldata userAddresses) external onlyOwner {
        update();
        require(passedUnlocksCount > 0, "SHO: no unlocks passed");
        uint32 currentUnlock = passedUnlocksCount - 1;
        require(currentUnlock < unlockPeriods.length - 1, "SHO: eliminating in the last unlock");

        for (uint256 i = 0; i < userAddresses.length; i++) {
            address userAddress = userAddresses[i];
            User memory user = users[userAddress];
            require(user.option == 1, "SHO: some user not option 1");
            require(user.feePercentageNextUnlock < HUNDRED_PERCENT, "SHO: some user already eliminated");

            uint128 unlockedTokens = _unlockUserTokens(user);
            uint32 increasedFeePercentage = _updateUserFee(user, HUNDRED_PERCENT);

            users[userAddress] = user;
            emit UserElimination(
                userAddress,
                currentUnlock,
                unlockedTokens,
                increasedFeePercentage
            );
        }
    }

    /**
        It's important that the fees are collectable not depedning on if users are claiming, 
        otherwise the fees could be collected when users claim.
     */ 
    function collectFees() external onlyFeeCollector nonReentrant returns (uint128 baseFee, uint128 extraFee) {
        update();
        require(collectedUnlocksCount < passedUnlocksCount, "SHO: no fees to collect");
        uint32 currentUnlock = passedUnlocksCount - 1;

        uint32 lastUnlockPercentage = collectedUnlocksCount > 0 ? unlockPercentages[collectedUnlocksCount - 1] : 0;
        uint128 lastExtraFee = collectedUnlocksCount > 0 ? extraFees[collectedUnlocksCount - 1] : 0;

        uint128 globalAllocation = globalTotalAllocation * (unlockPercentages[currentUnlock] - lastUnlockPercentage) / HUNDRED_PERCENT;
        baseFee = globalAllocation * initialFeePercentage / HUNDRED_PERCENT;
        extraFee = extraFees[currentUnlock] - lastExtraFee;
        uint128 totalFee = baseFee + extraFee;

        collectedUnlocksCount = currentUnlock + 1;
        shoToken.safeTransfer(msg.sender, totalFee);
        emit FeeCollection(
            currentUnlock,
            totalFee, 
            baseFee, 
            extraFee
        );
    }
    
//==== 4 Views======

/**
 View 1: AvailaibleToClaim
 View 2 Claim Button
 View 3 Total Allocation
 View 4 Total Claimed
*/
    function getTotalAllocation() external view returns (uint256){
        User memory user = users[msg.sender];
        return (user.allocation);
    }  
    
    function getAvailaibleToClaimed() external view returns (uint256){
        User memory user = users[msg.sender];
        return (user.totalUnlocked - user.totalClaimed);
    }

    function getTotalClaimed() external view returns (uint256){
        User memory user = users[msg.sender];
        return (user.totalClaimed);
    }

    /**
        Users can choose how much they want to claim and depending on that (ratio totalClaimed / totalUnlocked), 
        their fee for the next unlocks increases or not.
        @param amountToClaim needs to be less or equal to the available amount
     */
    function claim(
        uint128 amountToClaim
    ) external onlyWhitelisted nonReentrant returns (
        uint128 unlockedTokens,
        uint32 increasedFeePercentage,
        uint128 availableToClaim, 
        uint128 receivedTokens
    ) {
        update();
        User memory user = users[msg.sender];
        require(passedUnlocksCount > 0, "SHO: no unlocks passed");
        require(amountToClaim <= user.allocation, "SHO: amount to claim higher than allocation");
        uint32 currentUnlock = passedUnlocksCount - 1;

        unlockedTokens = _unlockUserTokens(user);

        availableToClaim = user.totalUnlocked - user.totalClaimed;
        require(availableToClaim > 0, "SHO: no tokens to claim");
        
        receivedTokens = amountToClaim > availableToClaim ? availableToClaim : amountToClaim;
        user.totalClaimed += receivedTokens;

        if (user.option == 0) {
            uint32 claimedRatio = uint32(user.totalClaimed * HUNDRED_PERCENT / user.totalUnlocked);
            increasedFeePercentage = _updateUserFee(user, claimedRatio);
        }
        
        users[msg.sender] = user;
        shoToken.safeTransfer(msg.sender, receivedTokens);
        emit Claim(
            msg.sender, 
            currentUnlock, 
            unlockedTokens,
            increasedFeePercentage,
            receivedTokens
        );
    }

    /**  
        Updates passedUnlocksCount.
        If there's a new unlock that is not the last unlock, 
        it updates extraFees array of the next unlock by using the extra fees of the new unlock.
    */
    function update() public {
        require(block.timestamp >= startTime, "SHO: before startTime");

        uint256 timeSinceStart = block.timestamp - startTime;
        uint256 maxReleases = unlockPeriods.length;
        uint32 _passedUnlocksCount = passedUnlocksCount;

        while (_passedUnlocksCount < maxReleases && timeSinceStart >= unlockPeriods[_passedUnlocksCount]) {
            _passedUnlocksCount++;
        }

        if (_passedUnlocksCount > passedUnlocksCount) {
            passedUnlocksCount = _passedUnlocksCount;

            uint32 currentUnlock = _passedUnlocksCount - 1;
            uint128 extraFeesAdded;
            if (currentUnlock < unlockPeriods.length - 1) {
                if (extraFees[currentUnlock + 1] == 0) {
                    uint32 unlockPercentageDiffCurrent = currentUnlock > 0 ?
                        unlockPercentages[currentUnlock] - unlockPercentages[currentUnlock - 1] : unlockPercentages[currentUnlock];
                    uint32 unlockPercentageDiffNext = unlockPercentages[currentUnlock + 1] - unlockPercentages[currentUnlock];
                    
                    extraFeesAdded = extraFees[currentUnlock + 1] = extraFees[currentUnlock] +
                        unlockPercentageDiffNext * extraFees[currentUnlock] / unlockPercentageDiffCurrent;
                }
            }
            emit Update(_passedUnlocksCount, extraFeesAdded);
        } 
    }

    function _updateUserFee(User memory user, uint32 potentiallyNextFeePercentage) private returns (uint32 increasedFeePercentage) {
        uint32 currentUnlock = passedUnlocksCount - 1;

        if (currentUnlock < unlockPeriods.length - 1) {
            if (potentiallyNextFeePercentage > user.feePercentageNextUnlock) {
                increasedFeePercentage = potentiallyNextFeePercentage - user.feePercentageNextUnlock;
                user.feePercentageNextUnlock = potentiallyNextFeePercentage;

                uint128 tokensNextUnlock = user.allocation * (unlockPercentages[currentUnlock + 1] - unlockPercentages[currentUnlock]) / HUNDRED_PERCENT;
                uint128 extraFee = tokensNextUnlock * increasedFeePercentage / HUNDRED_PERCENT;
                extraFees[currentUnlock + 1] += extraFee;
            }
        }
    }

    function _unlockUserTokens(User memory user) private view returns (uint128 unlockedTokens) {
        uint32 currentUnlock = passedUnlocksCount - 1;

        if (user.unlockedBatchesCount <= currentUnlock) {
            user.feePercentageCurrentUnlock = user.feePercentageNextUnlock;

            uint32 lastUnlockPercentage = user.unlockedBatchesCount > 0 ? unlockPercentages[user.unlockedBatchesCount - 1] : 0;
            unlockedTokens = user.allocation * (unlockPercentages[currentUnlock] - lastUnlockPercentage) / HUNDRED_PERCENT;
            unlockedTokens -= unlockedTokens * user.feePercentageCurrentUnlock / HUNDRED_PERCENT;
            user.totalUnlocked += unlockedTokens;
            user.unlockedBatchesCount = currentUnlock + 1;
        }
    }

    function _buildArraySum(uint32[] memory diffArray) internal pure returns (uint32[] memory) {
        uint256 len = diffArray.length;
        uint32[] memory sumArray = new uint32[](len);
        uint32 lastSum = 0;
        for (uint256 i = 0; i < len; i++) {
            if (i > 0) {
                lastSum = sumArray[i - 1];
            }
            sumArray[i] = lastSum + diffArray[i];
        }
        return sumArray;
    }
}


