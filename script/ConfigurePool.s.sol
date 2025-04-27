// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@chainlink/contracts-ccip/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink/local/lib/ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigurePool is Script {
    function run(
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken,
        bool outboundRateLimiterIsEnabled,
        uint128 outBoundRateLimiterCapacity,
        uint128 outBoundRateLimiterRate,
        bool inboundRateLimiterIsEnabled,
        uint128 inBoundRateLimiterCapacity,
        uint128 inBoundRateLimiterRate
    ) public {
        vm.startBroadcast();
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        RateLimiter.Config memory outboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: outboundRateLimiterIsEnabled,
            capacity: outBoundRateLimiterCapacity,
            rate: outBoundRateLimiterRate
        });

        RateLimiter.Config memory inboundRateLimiterConfig = RateLimiter.Config({
            isEnabled: inboundRateLimiterIsEnabled,
            capacity: inBoundRateLimiterCapacity,
            rate: inBoundRateLimiterRate
        });
        TokenPool.ChainUpdate[] memory chainToAdd = new TokenPool.ChainUpdate[](1);
        chainToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: outboundRateLimiterConfig,
            inboundRateLimiterConfig: inboundRateLimiterConfig
        });
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainToAdd);
        vm.stopBroadcast();
    }
}
