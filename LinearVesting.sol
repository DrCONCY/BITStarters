// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./utils/HasERC677TokenParent.sol";

//Allow the vesting of multiple users using only one contract.

contract LinearVesting is HasERC677TokenParent {
    //Events
    event Transfer(address indexed from, address indexed to, uint256 value);

    event VestingBegin(
        uint256 startDate
    );
   
    event TokensReleased(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint256 amount
    );

    event VestingCreated(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable
    );

    event VestingRevoked(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint256 refund
    );
   
    event VestingTransfered(
        uint256 indexed vestingId,
        address indexed from,
        address indexed to
    );

    struct Vesting {
        /** vesting id. */
        uint256 id;
        /** address that will receive the token. */
        address beneficiary;
        /** the amount of token to vest. */
        uint256 amount;
        /** the cliff time of the token vesting. */
        uint256 cliffDuration;
        /** the duration of the token vesting. */
        uint256 duration;
        /** whether the vesting can be revoked. */
        bool revocable;
        /** whether the vesting is revoked. */
        bool revoked;
        /** the amount of the token released. */
        uint256 released;
    }

    /** currently locked tokens that are being used by all of the vestings */
    uint256 public totalSupply;

    uint256 public startDate;

    /** mapping to vesting list */
    mapping(uint256 => Vesting) public vestings;

    /** mapping to list of address's owning vesting id */
    mapping(address => uint256[]) public owned;

    /** always incrementing value to generate the next vesting id */
    uint256 _idCounter;

    //Param BIT Token Address
    constructor(address bit) HasERC677TokenParent(bit) {}
  
    /**
     * @notice Create a new vesting. 
     *
     * @param beneficiary Address that will receive BIT tokens.
     * @param amount Amount of BIT to vest.
     * @param cliffDuration Cliff duration in seconds.
     * @param duration Vesting duration in seconds.
     */
    function vest(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable
    ) external onlyOwner onlyWhenNotStarted {
        require(duration > 0, "LinearVesting: Duration should be greater than zero");
        _vest(beneficiary, amount, cliffDuration, duration, revocable);
    }


    function vestMultiple(
        address[] calldata beneficiaries,
        uint256[] calldata amounts,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable
    ) external onlyOwner onlyWhenNotStarted {
        require(beneficiaries.length == amounts.length, "Arrays are not the same length");
        require(beneficiaries.length != 0, "Must vest at least one person");
        require(duration > 0, "LinearVesting: Duration should be greater than zero");

        for (uint256 index = 0; index < beneficiaries.length; ++index) {
            _vest(beneficiaries[index], amounts[index], cliffDuration, duration, revocable);
        }
    }

 //========= FUNCTIONS ======
    /**
     * Globally Begin the vesting of everyone at a specified timestamp.
     * @param timestamp Timestamp to use as a startDate.
     */
    function beginAt(uint256 timestamp) external onlyOwner {
        require(timestamp != 0, "Oops! Timestamp cannot be zero");
        _begin(timestamp);
    }

    /**
     * @notice Release the tokens of a specified vesting.     
     * @param vestingId Vesting ID to release.
     */
    function release(uint256 vestingId) external returns (uint256) {
        return _release(_getVesting(vestingId, _msgSender()));
    }

   //Release all unlocked tokens that has vested    
    function releaseAll() external returns (uint256) {
        return _releaseAll(_msgSender());
    }

    /**
     * Revoke a vesting.     
     * @param vestingId Vesting ID to revoke.
     * @param sendBack Should the revoked tokens stay in the contract or be sent back to the owner?
     */
    function revoke(uint256 vestingId, bool sendBack) public onlyOwner returns (uint256) {
        return _revoke(_getVesting(vestingId), sendBack);
    }

      /**
     * @notice Transfer a vesting to another person.     
     * @param to Receiving address.
     * @param vestingId Vesting ID to transfer.
     */
    function transfer(address to, uint256 vestingId) external {
        _transfer(_getVesting(vestingId, _msgSender()), to);
    }

    /**
     * @notice Send the available token back to the owner.
     */
    function emptyAvailableReserve() external onlyOwner {
        uint256 available = availableReserve();
        require(available > 0, "LinearVesting:: no token available");

        parentToken.transfer(owner(), available);
    }

    
    //============ VIEWS=========
    //Return User's Total Allocation
    function totalAllocation(address beneficiary) external view returns (uint256 balance) {
        uint256[] storage indexes = owned[beneficiary];

        for (uint256 index = 0; index < indexes.length; ++index) {
            uint256 vestingId = indexes[index];

            balance += userAllocation(vestingId);
        }
    }

    //REturn Claimed Tokens
    function claimedTokens(address beneficiary) external view returns (uint256 balance) {
        uint256[] storage indexes = owned[beneficiary];

        for (uint256 index = 0; index < indexes.length; ++index) {
            uint256 vestingId = indexes[index];

            balance += claimedTokens(vestingId);
        }
    }

    //Return Claimable Tokens
    function claimableTokens(address beneficiary) external view returns (uint256 balance) {
        uint256[] storage indexes = owned[beneficiary];

        for (uint256 index = 0; index < indexes.length; ++index) {
            uint256 vestingId = indexes[index];

            balance += releasableAmount(vestingId);
        }
    }
    
    //Return user's unlocked tokens
    function unlockedTokens(address beneficiary) external view returns (uint256 balance) {
        uint256[] storage indexes = owned[beneficiary];

        for (uint256 index = 0; index < indexes.length; ++index) {
            uint256 vestingId = indexes[index];

            balance += vestedAmount(vestingId);
        }
    }

   //======= MUTATIVE VIEWS ========
   /**
     * @notice Get the current reserve (or balance) of the contract in BIT.
     * @return The balance of BIT this contract has.
     */
    function reserve() public view returns (uint256) {
        return parentToken.balanceOf(address(this));
    }

    //return The number of BIT that can be used to create another vesting.
    function availableReserve() public view returns (uint256) {
        return reserve() - totalSupply;
    }

  //Return Name assigned to vested tokens
  function name() external pure returns (string memory) {
        return "vested BIT Starters";
    }

    function symbol() external pure returns (string memory) {
        return "vBIT";
    }

    //Get the number of vesting for an address.
    function ownedCount(address beneficiary) public view returns (uint256) {
        return owned[beneficiary].length;
    }

   //====== FUNCTIONS Internal Logic =======
   
     //Begin the vesting for everyone at a specified timeStamp
    function _begin(uint256 timestamp) internal onlyWhenNotStarted {
        startDate = timestamp;

        emit VestingBegin(startDate);
    }

    // Create a Vesting
    function _vest(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable
    ) internal {
        require(beneficiary != address(0), "LinearVesting: beneficiary is the zero address");
        require(amount > 0, "LinearVesting: amount is 0");
        require(availableReserve() >= amount, "LinearVesting: available reserve is not enough");

        uint256 vestingId = _idCounter++; /* post-increment */

        // prettier-ignore
        vestings[vestingId] = Vesting({
            id: vestingId,
            beneficiary: beneficiary,
            amount: amount,
            cliffDuration: cliffDuration,
            duration: duration,
            revocable: revocable,
            revoked: false,
            released: 0
        });

        _addOwnership(beneficiary, vestingId);

        totalSupply += amount;

        emit VestingCreated(vestingId, beneficiary, amount, cliffDuration, duration, revocable);
        emit Transfer(address(0), beneficiary, amount);
    }


    //Transfer a vesting to another address.
    function _transfer(Vesting storage vesting, address to) internal {
        address from = vesting.beneficiary;

        require(from != to, "LinearVesting:: cannot transfer to itself");
        require(to != address(0), "LinearVesting: target is the zero address");

        _removeOwnership(from, vesting.id);
        _addOwnership(to, vesting.id);

        vesting.beneficiary = to;

        emit VestingTransfered(vesting.id, from, to);
        emit Transfer(from, to, _balanceOfVesting(vesting));
    }


    // Revoke a vesting and send the extra CRUNCH back to the owner.
    function _revoke(Vesting storage vesting, bool sendBack) internal returns (uint256 refund) {
        require(vesting.revocable, "LinearVesting: token not revocable");
        require(!vesting.revoked, "LinearVesting: token already revoked");

        uint256 unreleased = _releasableAmount(vesting);
        refund = vesting.amount - vesting.released - unreleased;

        vesting.revoked = true;
        vesting.amount -= refund;
        totalSupply -= refund;

        if (sendBack) {
            parentToken.transfer(owner(), refund);
        }

        emit VestingRevoked(vesting.id, vesting.beneficiary, refund);
        emit Transfer(vesting.beneficiary, address(0), refund);
    }

    //Internal implementation of the release() method.
    //The methods will fail if there is no tokens due.
    function _release(Vesting storage vesting) internal returns (uint256 unreleased) {
        unreleased = _doRelease(vesting);
        _checkAmount(unreleased);
    }


    // Internal implementation of the releaseAll() method.
    function _releaseAll(address beneficiary) internal returns (uint256 unreleased) {
        uint256[] storage indexes = owned[beneficiary];

        for (uint256 index = 0; index < indexes.length; ++index) {
            uint256 vestingId = indexes[index];
            Vesting storage vesting = vestings[vestingId];

            unreleased += _doRelease(vesting);
        }

        _checkAmount(unreleased);
    }

    /**
     * @dev Actually releasing the vestiong.
     * @dev This method will not fail. (aside from a lack of reserve, which should never happen!)
     */
    function _doRelease(Vesting storage vesting) internal returns (uint256 unreleased) {
        unreleased = _releasableAmount(vesting);

        if (unreleased != 0) {
            parentToken.transfer(vesting.beneficiary, unreleased);

            vesting.released += unreleased;
            totalSupply -= unreleased;

            emit TokensReleased(vesting.id, vesting.beneficiary, unreleased);
            emit Transfer(vesting.beneficiary, address(0), unreleased);
        }
    }

    /**
     * @dev Revert the transaction if the value is zero.
     */
    function _checkAmount(uint256 unreleased) internal pure {
        require(unreleased > 0, "LinearVesting: no tokens are due");
    }
 

 //====== VIEWS INTERNAL LOGICS =========

    /**
     * @notice Get the amount of tokens (userAllocation, vested, claimed,  )
     * @param vestingId Vesting ID to check.
     * @return The vested amount of the vestings.
     */ 
  
    function userAllocation(uint256 vestingId) public view returns (uint256) {
        return _userAllocation(_getVesting(vestingId));
    }
    function vestedAmount(uint256 vestingId) public view returns (uint256) {
        return _vestedAmount(_getVesting(vestingId));
    }

    function releasableAmount(uint256 vestingId) public view returns (uint256) {
        return _releasableAmount(_getVesting(vestingId));
    }

    function balanceOfVesting(uint256 vestingId) public view returns (uint256) {
        return _balanceOfVesting(_getVesting(vestingId));
    }
    
    function claimedTokens(uint256 vestingId) public view returns (uint256) {
        return _claimedTokens(_getVesting(vestingId));
    }

//=========== VIEW LOGIC COMPUTATION================================= 

    //Compute the vested amount(unlocked tokens)
    function _vestedAmount(Vesting memory vesting) internal view returns (uint256) {
        if (startDate == 0) {
            return 0;
        }

        uint256 cliffEnd = startDate + vesting.cliffDuration;

        if (block.timestamp < cliffEnd) {
            return 0;
        }

        if ((block.timestamp >= cliffEnd + vesting.duration) || vesting.revoked) {
            return vesting.amount;
        }

        return (vesting.amount * (block.timestamp - cliffEnd)) / vesting.duration;
    }

    //Compute the releasable amount(claimable)
    function _releasableAmount(Vesting memory vesting) internal view returns (uint256) {
        return _vestedAmount(vesting) - vesting.released;
    }

    //Compute balance(locked tokens)
    function _balanceOfVesting(Vesting storage vesting) internal view returns (uint256) {
        return vesting.amount - vesting.released;
    }
    
    //Compute total tokens
    function _userAllocation(Vesting storage vesting) internal view returns (uint256) {
        return vesting.amount;
    }

    //Compute released tokens(claimed)
    function _claimedTokens(Vesting storage vesting) internal view returns (uint256) {
        return vesting.released;
    }

    /**
     * @dev Get a vesting.
     * @return vesting struct stored in the storage.
     */
    function _getVesting(uint256 vestingId) internal view returns (Vesting storage vesting) {
        vesting = vestings[vestingId];
        require(vesting.beneficiary != address(0), "LinearVesting: vesting does not exists");
    }

    /**
     * @dev Get a vesting and make sure it is from the right beneficiary.
     * @param beneficiary Address to get it from.
     * @return vesting struct stored in the storage.
     */
    function _getVesting(uint256 vestingId, address beneficiary) internal view returns (Vesting storage vesting) {
        vesting = _getVesting(vestingId);
        require(vesting.beneficiary == beneficiary, "LinearVesting: not the beneficiary");
    }

   //Test if an address is the beneficiary of a vesting.
    function isBeneficiary(uint256 vestingId, address account) public view returns (bool) {
        return _isBeneficiary(_getVesting(vestingId), account);
    }

    /**
     * @dev Test if the vesting's beneficiary is the same as the specified address.
     */
    function _isBeneficiary(Vesting storage vesting, address account) internal view returns (bool) {
        return vesting.beneficiary == account;
    }

    //Test if an address has at least one vesting.
    function isVested(address beneficiary) public view returns (bool) {
        return ownedCount(beneficiary) != 0;
    }


    /**
     * @dev Remove the vesting from the ownership mapping.
     */
    function _removeOwnership(address account, uint256 vestingId) internal returns (bool) {
        uint256[] storage indexes = owned[account];

        (bool found, uint256 index) = _indexOf(indexes, vestingId);
        if (!found) {
            return false;
        }

        if (indexes.length <= 1) {
            delete owned[account];
        } else {
            indexes[index] = indexes[indexes.length - 1];
            indexes.pop();
        }

        return true;
    }

    /**
     * @dev Add the vesting ID to the ownership mapping.
     */
    function _addOwnership(address account, uint256 vestingId) internal {
        owned[account].push(vestingId);
    }

    /**
     * @dev Find the index of a value in an array.
     * @param array Haystack.
     * @param value Needle.
     * @return If the first value is `true`, that mean that the needle has been found and the index is stored in the second value. Else if `false`, the value isn't in the array and the second value should be discarded.
     */
    function _indexOf(uint256[] storage array, uint256 value) internal view returns (bool, uint256) {
        for (uint256 index = 0; index < array.length; ++index) {
            if (array[index] == value) {
                return (true, index);
            }
        }

        return (false, 0);
    }

    /**
     * @dev Revert if the start date is not zero.
     */
    modifier onlyWhenNotStarted() {
        require(startDate == 0, "LinearVesting: already started");
        _;
    }
}