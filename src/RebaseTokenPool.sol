// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {TokenPool, IERC20, RateLimiter} from "@chainlink/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IPoolV1} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IPool.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

/**
 * @title RebaseTokenPool - Custom implementation of TokenPool for rebase tokens
 * @author Aashim
 * @notice This contract extends Chainlink's TokenPool to handle rebase tokens with custom interest rates
 * @dev https://github.com/smartcontractkit/ccip/blob/release/contracts-ccip-1.5.1/contracts/src/v0.8/ccip/pools/BurnMintTokenPoolAbstract.sol
 * @dev The burn operation works differently than standard ERC20 - see detailed comments below
 */
contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address[] memory _allowList, address _rmnProxy, address _router)
        TokenPool(_token, 18, _allowList, _rmnProxy, _router)
    {}

    /**
     * @notice Handles locking or burning tokens when sending to another chain
     * @dev The burn operation is unique because:
     * 1. User first approves tokens to CCIP router
     * 2. User initiates CCIP transfer
     * 3. CCIP router pulls tokens to this TokenPool contract
     * 4. We burn FROM this contract's balance (not the original user's)
     *
     * This is different from standard ERC20 where you'd burn from user's address directly
     *
     * @param lockOrBurnIn Contains transfer details including encoded receiver address
     * @return lockOrBurnOut Output structure (currently empty in this implementation)
     */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);

        // Decode receiver address from ABI-encoded bytes
        address originalSender = lockOrBurnIn.originalSender;

        // Get the receiver's custom interest rate from the rebase token
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(originalSender);

        /**
         * @dev Burns tokens from this contract's balance
         * - address(this) is the "from" address because CCIP has already transferred
         *   the tokens to this contract before calling lockOrBurn
         * - This is a two-step process:
         *   1. Tokens moved from user -> this contract (by CCIP router)
         *   2. We burn from this contract's balance
         */
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /**
     * @notice Releases/mints tokens when receiving from another chain
     * @param releaseOrMintIn Contains transfer details {
     *   address receiver,
     *   uint256 amount,
     *   bytes sourcePoolData (encoded interest rate)
     * }
     * @return releaseOrMintOut Output structure {
     *   uint256 destinationAmount
     * }
     */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);
        // Decode interest rate from source chain.
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        //  // Mint tokens to receiver with their custom interest rate
        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);
        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
