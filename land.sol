// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interface for ERC20 token
interface IERC20 {
    // transfer token from the account called this function to recipient account
    function transfer(address recipient, uint256 amount) external returns (bool);
    // transfer token between accounts
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    // check the balance of an given account
    function balanceOf(address account) external view returns (uint256);
}

contract LendingPool {
    mapping(address => uint256)public userBalance;
    mapping(address => uint256[])public WithdrawTime;
    event Withdrawn(
        address userAddress, 
        uint256 amount,
        uint256 withdrawTime
    );

    // Define the structure of a deposit
    struct Deposit {
        address depositAccount;
        uint256 amount;
        uint256 depositTime;
        bool withdrawn;
    }

    address public userAddress;
    address public fundPool;
    uint256 public interestRate = 1;    // 1% interest rate
    uint256 public duration = 365 days; // Duration of 1 year
    
    mapping(address => Deposit) public deposits;

    // Constructor to set the token address and the fund pool address
    constructor(address _userAddress, address _fundPool) {
        userAddress = _userAddress;
        fundPool = _fundPool;
    }

    function interestCalculator(uint256 _amount) public view returns (uint256 _interest){
        uint256 interest = (_amount * interestRate) / 100;
        return interest;
    }

    function deposit(uint256 _amount) public {
        require(_amount > 0, "Deposit amount must more than zero");

        // Check if the user has enough balance
        uint256 userBalance = IERC20(userAddress).balanceOf(msg.sender);
        require(userBalance >= _amount, "Insufficient balance");

        // Transfer tokens from the sender to the fund pool
        IERC20(userAddress).transferFrom(msg.sender, fundPool, _amount);

        // Record deposit details on the block
        deposits[msg.sender] = Deposit({
            depositAccount: msg.sender,
            amount: _amount,
            depositTime: block.timestamp,
            withdrawn: false
        });
    }
    // withdraw
    function withdraw(uint256 _amount) payable external  {
         require(_amount > 0,"Please enter a valid amount");
         require(_amount <= userBalance[msg.sender], "Insufficient balance");
         userBalance[msg.sender] -= _amount;
         payable(msg.sender).transfer(_amount);
         WithdrawTime[msg.sender].push(block.timestamp);
        emit Withdrawn(msg.sender, _amount,block.timestamp);

    }
    //check the balace 
    function balanceOf(address userAddress) override public view returns (uint256) {
         return userBalance[userAddress];
    }
    function updateBalance(address _userAddress) internal {
        if (userBalance[_userAddress] > 0) {
            uint256 interest = interestCalculator(deposits[_userAddress].amount);
            userBalance[_userAddress] += interest;
            deposits[_userAddress].depositTime = block.timestamp;
        }
}
