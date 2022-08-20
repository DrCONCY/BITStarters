// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

import "./access/SafeERC20.sol";
import "./access//Ownable.sol";

interface ISHO{
    function mint(address account_, uint256 amount_) external;
}

contract SHOdeposit is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount; // Amount USDT deposited by user
        uint256 debt; // total SHO claimed thus SHO debt
        bool claimed; // True if a user has claimed SHO
    }
    // Tokens to raise (USDT) for offer (SHO) which can be swapped for (SHO)
    IERC20 public USDT; // for user deposits

    IERC20 public SHO;

    address public DAO; // Multisig treasury to send raised funds to

    uint256 public price = 1* 1e18; // 1 USDT per SHO

    uint256 public cap = 200 * 1e18; // 200 USDT per whitelisted user
    uint256 public minPurchase = 100 * 1e18; // 100 USDT Minimum Purchase
    uint256 public maxPurchase = 200 * 1e18; // 200 USDT Maximum Purchase

    uint256 public totalRaisedUSDT; // total USDT raised by sale

    uint256 public totalDebt; // total SHO and thus SHO owed to users

    
    bool public started; // true when sale is started

    bool public ended; // true when sale is ended

    bool public contractPaused; // circuit breaker

    mapping(address => UserInfo) public userInfo;

    mapping(address => bool) public whitelisted; // True if user is whitelisted

    event Deposit(address indexed who, uint256 amount);
    event SaleStarted(uint256 block);
    event SaleEnded(uint256 block);
    event AdminWithdrawal(address token, uint256 amount);

    constructor(
        address _SHO,
        address _USDT,
        address _DAO
    ) {
        require( _SHO != address(0) );
        SHO = IERC20(_SHO);
        require( _USDT != address(0) );
        USDT = IERC20(_USDT);
        require( _DAO != address(0) );
        DAO = _DAO;
    }

    //* @notice modifer to check if contract is paused
    modifier checkIfPaused() {
        require(contractPaused == false, "contract is paused");
        _;
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
        require(_addresses.length <= 333,"too many addresses");
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelisted[_addresses[i]] = true;
        }
    }

    /**
     *  @notice removes a single whitelist from the sale
     *  @param _address: address to remove from whitelist
     */
    function removeWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = false;
    }

    // @notice Starts the sale
    function start() external onlyOwner {
        require(!started, "Sale has already started");
        started = true;
        emit SaleStarted(block.number);
    }

    // @notice Ends the sale
    function end() external onlyOwner {
        require(started, "Sale has not started");
        require(!ended, "Sale has already ended");
        ended = true;
        emit SaleEnded(block.number);
    }

    // @notice lets owner pause contract
    function togglePause() external onlyOwner returns (bool){
        contractPaused = !contractPaused;
        return contractPaused;
    }
    /**
     *  @notice transfer ERC20 token to DAO multisig
     *  @param _token: token address to withdraw
     *  @param _amount: amount of token to withdraw
     */
    function adminWithdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20( _token ).safeTransfer( address(msg.sender), _amount );
        emit AdminWithdrawal(_token, _amount);
    }

    /**
     *  @notice it deposits USDT for the sale
     *  @param _amount: amount of USDT to deposit to sale (18 decimals)
     */
    function deposit(uint256 _amount) external checkIfPaused {
        require(started, "Sale has not started");
        require(!ended, "Sale has ended");
        require(totalRaisedUSDT <= 90*1e21, "SoldOut!");//Change to $80k or 100k dependding on the amount being raised
        require(whitelisted[msg.sender] == true, "Sorry! Address not whitelisted.");
        require(_amount >= minPurchase, "Min Purchase is $100" );
        require(_amount >= maxPurchase, "Max Purchase is $200");     
        
        UserInfo storage user = userInfo[msg.sender];

        require(
            cap >= user.amount.add(_amount),
            "Each whilisted address is capped at $200"
            );

        user.amount = user.amount.add(_amount);
        totalRaisedUSDT = totalRaisedUSDT.add(_amount);

        uint256 payout = _amount.mul(1e18).div(price).div(1e9); // SHO to mint for _amount

        totalDebt = totalDebt.add(payout);

        USDT.safeTransferFrom( msg.sender, DAO, _amount );

        ISHO( address(SHO) ).mint( msg.sender, payout );

        emit Deposit(msg.sender, _amount);
    }

    // @notice it checks a users USDT allocation remaining
    function getUserRemainingAllocation(address _user) external view returns ( uint256 ) {
        UserInfo memory user = userInfo[_user];
        return cap.sub(user.amount);
    }

}