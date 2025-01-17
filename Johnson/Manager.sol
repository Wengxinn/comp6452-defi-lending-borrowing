// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BorrowContract.sol";
import "./WBTC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract Manager {

  // Struct to store user collateral (For a specific user, how much ETH and wBTC they have)
  struct UserCollateral {
      uint ethAmount;
      uint wBtcAmount;
  }


  // For now, fixed exchange rate: 1 BTC = 10 ETH
  // Later, will change it to a dynamic exchange rate (oracle)
  uint exchangeRate = 10;

  // The owner of the manager, this address will be the pool address (assumption)
  address public owner;

  // Wrapped BTC token
  IERC20 public wBtc;

  // Total number of loans in the pool
  uint public totalLoans;

  // List of addresses of loans (address, BorrowContract)
  mapping (address => BorrowContract) public loans;
  
  // List to track if loan exists (loan address, bool)
  mapping (address => bool) private _loanExists;

  // List of user collaterals (user address, UserCollateral)
  mapping (address => UserCollateral) public collaterals;

  // List to track if user collateral exists (user address, bool)
  mapping (address => bool) private _collateralExists;


  // ===========================================================================================================================================================
  // Event to be emitted when a new BorrowContract is initialized, not yet finalized
  event BorrowContractInitialized(address BorrowContractAddress, uint borrowAmount, bool wantBTC, bool activated);

  // Event to be emiited when a new BorrowContract is activated
  event BorrowContractActivated(address BorrowContractAddress, uint borrowAmount, bool wantBTC, uint exchangeRate);
  // ===========================================================================================================================================================


  constructor() {
    // Set contract creator as the owner
    owner = msg.sender;

    // Set initial number of loans
    totalLoans = 0;

    wBtc = new WBTC(msg.sender, 1000000000000000000000000);
    approveWBTC(1000000000000000000000000);
  }

  // Function to get the current exchange rate
  function _getExchangeRate() public view returns (uint) {
    return exchangeRate;
  }

  // Function to approve the manager to spend wBTC
  function approveWBTC(uint amount) public {
    require(msg.sender == owner, "Only owner can approve wBTC");
    require(amount > 0, "Amount must be greater than 0");
    require(wBtc.approve(owner, amount), "Approval failed");
    require(wBtc.approve(address(this), amount), "Approval failed");
  }



  // Function to calculate the collateral amount needed for a loan
  function _calculateCollateralAmount(uint loanAmount, bool wantBTC, uint currentExchangeRate) private pure returns (uint) {
    return wantBTC ? loanAmount * currentExchangeRate : loanAmount / currentExchangeRate;
  }


  // Function to deploy a new BorrowContract, but not yet set the collateral
  // When the new borrow contract is initialized, the function will return the address of the new BorrowContract
  // And the caller can call the depositCollateral function to set the collateral
  function deployBorrowContract(uint brorowAmount, bool wantBTC) public returns (address) {
      require(brorowAmount > 0, "Borrow amount must be greater than 0");

      // Check if the owner has enough currency to lend
      if (wantBTC) {
        require(wBtc.balanceOf(owner) >= brorowAmount, "Owner does not have enough wBTC");
      } else {
        require(owner.balance >= brorowAmount, "Owner does not have enough ETH");
      }

      // Get the current exchange rate.
      uint currentExchangeRate = _getExchangeRate();

      // Calculate collateral amount required
      uint collateralAmount = _calculateCollateralAmount(brorowAmount, wantBTC, currentExchangeRate);
      
      // Create new loan instance
      BorrowContract newBorrowContract = new BorrowContract(msg.sender, wBtc, brorowAmount, wantBTC, collateralAmount, currentExchangeRate, false);

      // Add loan address to the pool
      loans[msg.sender] = newBorrowContract;
      _loanExists[address(newBorrowContract)] = true;
      totalLoans++;

      emit BorrowContractInitialized(address(newBorrowContract), brorowAmount, wantBTC, false);
      return address(newBorrowContract);
  }



  // Function to deposit collateral to a specific BorrowContract -> Deposit ETH
  function depositCollateralETH(address borrowContractAddress) public payable {
    // Check if the BorrowContract exists
    require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
    BorrowContract borrowContract = BorrowContract(borrowContractAddress);

    require(msg.sender == borrowContract.borrower(), "Only borrower can deposit collateral");

    if (borrowContract.wantBTC()) {
      borrowContract.depositCollateralETH{value: msg.value}(owner);
    } else {
      revert("This BorrowContract does not support ETH collateral");
    }
    emit BorrowContractActivated(borrowContractAddress, borrowContract.borrowAmount(), borrowContract.wantBTC(), borrowContract.exchangeRate());
  }



  // Function to deposit collateral to a specific BorrowContract -> Deposit wBTC
  function depositCollateralBTC(address borrowContractAddress, uint _wBtcCollateral) public {
    // Check if the BorrowContract exists
    require(_loanExists[borrowContractAddress], "BorrowContract does not exist");
    BorrowContract borrowContract = BorrowContract(borrowContractAddress);
    require(msg.sender == borrowContract.borrower(), "Only borrower can deposit collateral");

    if (!borrowContract.wantBTC()) {
      borrowContract.depositCollateralBTC(_wBtcCollateral);

      require(wBtc.transferFrom(msg.sender, owner, _wBtcCollateral), "WBTC transfer failed");
    } else {
      revert("This BorrowContract does not support BTC collateral");
    }
    emit BorrowContractActivated(msg.sender, borrowContract.borrowAmount(), borrowContract.wantBTC(), borrowContract.exchangeRate());
  }


  function checkWBTCBalance(address user) public view returns (uint) {
    return wBtc.balanceOf(user);
  }


  // Function to fund a user with wBTC
  function fundWBTC(address user, uint amount) public {
    require(msg.sender == owner, "Only owner can fund wBTC");
    require(amount > 0, "Amount must be greater than 0");
    // Check if the contract has enough wBTC to transfer
    uint contractBalance = wBtc.balanceOf(owner);
    require(contractBalance >= amount, "Contract does not have enough wBTC");

    // Transfer wBTC to the user from the owner
    require(wBtc.transferFrom(owner, user, amount), "WBTC transfer failed");
  }

  // ====================================================================================================

  // Function to get the exchangeRate of a specific BorrowContract
  function getBorrowContractExchangeRate(address borrowContractAddress) public view returns (uint) {
    BorrowContract borrowContract = BorrowContract(borrowContractAddress);
    return borrowContract.exchangeRate();
  }


  // Function to get the needed collateral amount of a specific BorrowContract
  function getCollateralAmount(address borrowContractAddress) public view returns (uint) {
    BorrowContract borrowContract = BorrowContract(borrowContractAddress);
    return borrowContract.collateralAmount();
  }

  // Function to get the status of a specific BorrowContract
  function getBorrowContractStatus(address borrowContractAddress) public view returns (bool) {
    BorrowContract borrowContract = BorrowContract(borrowContractAddress);
    return borrowContract.activated();
  }

  function getBorrowContractCreator(address borrowContractAddress) public view returns (address) {
    BorrowContract borrowContract = BorrowContract(borrowContractAddress);
    return borrowContract.creditors();
  }

  // Function to get the amount of ETH owned by the owner
  function getOwnerEthBalance() public view returns (uint) {
    return owner.balance;
  }

}