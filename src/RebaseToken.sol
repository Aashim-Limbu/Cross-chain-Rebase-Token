// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {console} from "forge-std/Test.sol";

/**
 * @title Rebase Token.
 * @author Aashim Limbu.
 * @notice This is a cross-chain rebase token that incentivises user to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in smart contract can only decrease.
 * @notice Each users will have their own interest rate that is global interest rate at the time of depositing.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateShouldOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // this interest rate is per second 5*10^10--> 5 x 10^-8 --> 5 x 10 ^-6 %
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 lastTimestamp) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     *
     * @param _interestRate Set the new global interest to _interestRate.
     * @dev The interest rate could only decrease.
     */
    function setInterestRate(uint256 _interestRate) external onlyOwner {
        if (_interestRate > s_interestRate) {
            revert RebaseToken__InterestRateShouldOnlyDecrease(s_interestRate, _interestRate);
        }
        s_interestRate = _interestRate;
        emit InterestRateSet(_interestRate);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        /**
         * @notice We need to implement this in the redeem function itself.
         *     if (_amount == type(uint256).max) {
         *         // There could be delay in block execution for redeem all of their balance
         *         _amount = balanceOf(_from);
         *     }
         */
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculates the user's balance, including accrued interest since the last update.
     * @dev Computes the total balance as the sum of the principal balance and accrued interest.
     * @param _user The address of the user whose balance is being calculated.
     * @return balance The total balance of the user, including accrued interest.
     * @dev we're actually showing the actual accruedBalance while we're left to mint as it require transaction.
     */
    function balanceOf(address _user) public view override returns (uint256 balance) {
        // get the current principle balance of user ( the number of tokens that have actually been minted )
        // multiply the principle balance by the interest that has accumulated in the time since the balance was last updated
        // principle_amount (1+ s_userInterestRate[_user] * time_elapsed)
        balance = (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR; // 1e18 * 1e18 --> 1e18
    }

    /**
     * @notice Transfer token from one to other user.
     * @param _recipient The user to which token is transfered into.
     * @param _amount The amount of Token to be transferred.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender); // the user want to send their whole balance
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender]; // set the reciever interest same as of the sender . It should not have the contract interest rate at the moment.
        }

        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Mint the accrued interest to user since the last time they intereacted with protocol (e.g., burn, mint , transfer)
     * @param _user The user to mint the accrued interest to .
     */
    function _mintAccruedInterest(address _user) internal {
        // 1. Find their current balance of rebase tokens that have been minted to the user. Represented As --> principle
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // 2. Calculate their current balance including any interest. Represented As --> balanceOf [It contain actual balance for user that need to be minted]
        uint256 actualBalance = balanceOf(_user);
        // 3. Calculate the number of tokens that need to be minted to users. (2.) - (1.)
        uint256 balanceIncrease = actualBalance - previousPrincipleBalance;
        console.log("balanceIncrease", balanceIncrease);
        // set users last updated timestamp
        // CEI -> Checks, Effect and Interactions
        s_userLastUpdatedTimestamp[_user] = block.timestamp; // [ Effect ]
        // call mint to mint token to the user
        _mint(_user, balanceIncrease); // [ Interactions ]
    }

    /**
     *
     * @param _user user to who we're finding the interest.
     * @return acumulatedInterest The linear Interest to be returned.
     */
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
        acumulatedInterest = (1 * PRECISION_FACTOR + s_userInterestRate[_user] * timeElapsed); // converting to same decimal factor --> 1e18
    }

    /**
     * @notice  Get the principle balance of user. This is the number of token that have been minted to a user, not including the accrued interest
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    function getUserInterestRate(address _user) external view returns (uint256 interestRate) {
        interestRate = s_userInterestRate[_user];
    }

    /**
     * @notice Get interest rate for contract. Any future depositor will recieve this interest.
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getMintAndBurnRole() external pure returns (bytes32) {
        return MINT_AND_BURN_ROLE;
    }
}
