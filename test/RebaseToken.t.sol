// SPDX-License-Identifier: MTI
pragma solidity >= 0.8.0 < 0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken, Ownable} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(address(rebaseToken));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testInterestIsLinear(uint256 amount) public {
        // vm.assume(amount > 1e5); // we try to conserve the run as much as possible via use of bound.
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        //check out rebase Token Balance.
        uint256 startingBalance = rebaseToken.balanceOf(user);
        console.log("startingBalance", startingBalance);
        assertEq(startingBalance, amount);
        //warp the time and checking the balance again --> increasing the time and checking the interest accrued.
        vm.warp(block.timestamp + 1 hours);
        uint256 intermediateBalance = rebaseToken.balanceOf(user);
        assertGt(intermediateBalance, startingBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, intermediateBalance);

        //check if the interest on same principle is same over same intervalOf Time.
        assertApproxEqAbs(intermediateBalance - startingBalance, endBalance - intermediateBalance, 1); // approx due to truncation with tolerance 1
        vm.stopPrank();
    }

    function testRedeemImmediately(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        //deposit
        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        //testRedeemImmediately
        vm.prank(user);
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 timeElapsed) public {
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        timeElapsed = bound(timeElapsed, 1000, type(uint24).max);
        vm.startPrank(user);
        vm.deal(user, depositAmount);
        // 1. Depositing
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        vm.warp(block.timestamp + timeElapsed);
        uint256 balance = rebaseToken.balanceOf(user);

        vm.prank(owner);
        vm.deal(owner, balance - depositAmount);
        addRewardToVault(balance - depositAmount);

        vm.prank(user);
        vault.redeem(type(uint256).max);
        uint256 userEthBalance = address(user).balance;
        assertEq(userEthBalance, balance);
        assertGt(userEthBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2 * 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        /*//////////////////////////////////////////////////////////////
                               DEPOSITING
        //////////////////////////////////////////////////////////////*/

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("USER2"); // reciever
        uint256 user2InitialBalance = rebaseToken.balanceOf(user2);
        uint256 userInitialBalance = rebaseToken.balanceOf(user);
        assertEq(user2InitialBalance, 0);
        assertEq(userInitialBalance, amount);

        // owner reduces the interest rate for our rebase token.
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10); // From 5e10 --> 4e10

        assertLt(rebaseToken.getInterestRate(), initialInterestRate);
        /*//////////////////////////////////////////////////////////////
                        TRANSFER
        //////////////////////////////////////////////////////////////*/
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 user2InterestRate = rebaseToken.getUserInterestRate(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(amountToSend, user2BalanceAfterTransfer);
        assertEq(userInitialBalance, userBalanceAfterTransfer + amountToSend);
        assertEq(userInterestRate, user2InterestRate);
    }

    function testInterestRateCannotBeSetExcludingOwner(uint256 interestRate) public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        rebaseToken.setInterestRate(interestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, rebaseToken.getMintAndBurnRole()
            )
        );
        rebaseToken.mint(user, 100);
        vm.stopPrank();
        console.logBytes32(rebaseToken.getMintAndBurnRole());
    }
}
