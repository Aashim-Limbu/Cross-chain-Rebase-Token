// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Rebase Token.
 * @author Aashim Limbu.
 * @notice This is a cross-chain rebase token that incentivises user to deposit into a vault and gain interest in rewards.
 * @notice The intereset rate in smart contract can only decrease.
 * @notice Each users will have their own interest rate that is global interest rate at the time of depositing.
 */
contract RebaseToken is ERC20 {
    error RebaseToken__InterestRateShouldOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private s_interestRate = 5e10; // this interest rate is per second
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 lastTimestamp) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") {}

    function setInterestRate(uint256 _interestRate) external {
        if (_interestRate < s_interestRate) {
            revert RebaseToken__InterestRateShouldOnlyDecrease(s_interestRate, _interestRate);
        }
        s_interestRate = _interestRate;
        emit InterestRateSet(_interestRate);
    }

    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[msg.sender] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Calculates the user's balance, including accrued interest since the last update.
     * @dev Computes the total balance as the sum of the principal balance and accrued interest.
     * @param _user The address of the user whose balance is being calculated.
     * @return balance The total balance of the user, including accrued interest.
     */
    function balanceOf(address _user) public view override returns (uint256 balance) {
        // get the current principle balance of user ( the number of tokens that have actually been minted )
        // multiply the principle balance by the interest that has accumulated in the time since the balance was last updated
        // principle_amount (1+ s_userInterestRate[_user] * time_elapsed) 
        balance = super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user);
    }

    function _mintAccruedInterest(address _user) internal {
        // 1. Find their current balance of rebase tokens that have been minted to the user. Represented As --> principle
        // 2. Calculate their current balance including any interest. Represented As --> balanceOf
        // 3. Calculate the number of tokens that need to be minted to users. (2.) - (1.)
        // call mint to mint token to the user
        // set users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 acumulatedInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // This interest will be linear growth with time.
        // 1. Calculate the time since the update .
        // 2. Calculate the amount of linear growth . principle_amount + principle_amount * user_interest * time_elapsed => principle_amount ( 1 + user_interest * time_elapsed );
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        acumulatedInterest = (1 + s_userInterestRate[_user] * timeElapsed);
    }

    function getUserInterestRate(address _user) external view returns (uint256 interestRate) {
        interestRate = s_userInterestRate[_user];
    }
}
