// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0 < 0.9.0;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // 1. Manage the Rebase Token (e.g., Depositing and withdrawing)
    // 2. Deposit function that mint the token equal to amount of ETH deposited.
    // 3. Redeem Function that burns the token and sends user ETH.
    // 4. Function to add reward to Vault.

    IRebaseToken private rebaseToken;

    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    error VAULT__REDEEM_FAILED();

    constructor(address _rebaseToken) {
        rebaseToken = IRebaseToken(_rebaseToken);
    }

    receive() external payable {}

    /**
     * @notice Allow users to deposit ETH into the vault and mint rebase token in return.
     */
    function deposit() external payable {
        uint256 interestRate = rebaseToken.getInterestRate();
        rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their rebase Token for ETH.
     * @param _amount The amount of rebase token to redeem.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = rebaseToken.balanceOf(msg.sender);
        }
        rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert VAULT__REDEEM_FAILED();
        }
        emit Redeemed(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address rebaseTokenAddress) {
        rebaseTokenAddress = address(rebaseToken);
    }
}
