// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool, IERC20, TokenPool, RateLimiter} from "../src/RebaseTokenPool.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {RegistryModuleOwnerCustom} from
    "@chainlink/contracts-ccip/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {Vault} from "../src/Vault.sol";
import {TokenAdminRegistry} from "@chainlink/contracts-ccip/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    uint256 ethSepoliaFork;
    uint256 optimismSepoliaFork;
    string ETHEREUM_SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    string OPTIMISM_SEPOLIA_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    RebaseToken ethSepoliaToken;
    RebaseToken optimismSepoliaToken;
    Vault vault;
    RebaseTokenPool ethSepoliaPool;
    RebaseTokenPool optimismSepoliaPool;
    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails optimismSepoliaNetworkDetails;

    address owner = makeAddr("OWNER");
    address user = makeAddr("USER");
    uint256 constant SEND_VALUE = 1e5;

    function setUp() public {
        /**
         * @dev Configuring CCIP Local Simulator with forked environment in  Foundry Project.
         */
        ethSepoliaFork = vm.createFork(ETHEREUM_SEPOLIA_RPC_URL);
        optimismSepoliaFork = vm.createFork(OPTIMISM_SEPOLIA_RPC_URL);
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));
        /**
         * @dev Now Enabling Rebase Tokens in CCIP. Registering from an EOA .
         */
        vm.selectFork(ethSepoliaFork);
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);

        // 1. Deploying Tokens
        ethSepoliaToken = new RebaseToken();
        vault = new Vault(address(ethSepoliaToken));

        // 2. Deploying Token Pools.
        ethSepoliaPool = new RebaseTokenPool(
            IERC20(address(ethSepoliaToken)),
            new address[](0),
            ethSepoliaNetworkDetails.rmnProxyAddress,
            ethSepoliaNetworkDetails.routerAddress
        );

        // 3. Claiming Burn and Mint Roles for token pools.
        ethSepoliaToken.grantMintAndBurnRole(address(vault));
        ethSepoliaToken.grantMintAndBurnRole(address(ethSepoliaPool));

        // 4. Claiming and Accepting the Admin Role.
        // Claiming Admin Role
        RegistryModuleOwnerCustom(ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(ethSepoliaToken)
        );
        // Accepting Admin Role
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(ethSepoliaToken));
        // 5. Linking Tokens to Pools.
        TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(ethSepoliaToken), address(ethSepoliaPool)
        );
        vm.stopPrank();

        // Deploy and configure on optimism Sepolia.
        vm.selectFork(optimismSepoliaFork);
        optimismSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        optimismSepoliaToken = new RebaseToken();
        optimismSepoliaPool = new RebaseTokenPool(
            IERC20(address(optimismSepoliaToken)),
            new address[](0),
            optimismSepoliaNetworkDetails.rmnProxyAddress,
            optimismSepoliaNetworkDetails.routerAddress
        );
        optimismSepoliaToken.grantMintAndBurnRole(address(vault));
        optimismSepoliaToken.grantMintAndBurnRole(address(optimismSepoliaPool));
        RegistryModuleOwnerCustom(optimismSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(optimismSepoliaToken)
        );
        TokenAdminRegistry(optimismSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(
            address(optimismSepoliaToken)
        );
        TokenAdminRegistry(optimismSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(optimismSepoliaToken), address(optimismSepoliaPool)
        );
        vm.stopPrank();

        // 6. Configuring Tokens Pools.
        configureTokenPool(
            ethSepoliaFork,
            TokenPool(address(ethSepoliaPool)),
            optimismSepoliaNetworkDetails.chainSelector,
            address(optimismSepoliaPool),
            address(optimismSepoliaToken)
        );
        configureTokenPool(
            optimismSepoliaFork,
            TokenPool(address(optimismSepoliaPool)),
            ethSepoliaNetworkDetails.chainSelector,
            address(ethSepoliaPool),
            address(ethSepoliaToken)
        );
    }

    function configureTokenPool(
        uint256 selectedFork,
        TokenPool localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) public {
        vm.selectFork(selectedFork);
        vm.prank(owner);
        bytes[] memory remotePoolAddress = new bytes[](1);
        remotePoolAddress[0] = abi.encode(remotePool);
        bytes memory remoteTokenAddress = abi.encode(remoteToken);

        // No Rate limitting.
        RateLimiter.Config memory outboundRateLimiterConfig =
            RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0});
        RateLimiter.Config memory inboundRateLimiterConfig =
            RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0});

        TokenPool.ChainUpdate[] memory chainToAdd = new TokenPool.ChainUpdate[](1);
        chainToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddress,
            remoteTokenAddress: remoteTokenAddress,
            outboundRateLimiterConfig: outboundRateLimiterConfig,
            inboundRateLimiterConfig: inboundRateLimiterConfig
        });
        localPool.applyChainUpdates(new uint64[](0), chainToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 500_000, allowOutOfOrderExecution: false}))
        });
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);
        vm.startPrank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        uint256 localBalanceBefore = localToken.balanceOf(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 localBalanceAfter = localToken.balanceOf(user);
        vm.stopPrank();
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);
        assertEq(localUserInterestRate, remoteUserInterestRate);
    }

    function testBridgeAllTokens() public {
        vm.selectFork(ethSepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(ethSepoliaToken.balanceOf(user), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            ethSepoliaFork,
            optimismSepoliaFork,
            ethSepoliaNetworkDetails,
            optimismSepoliaNetworkDetails,
            ethSepoliaToken,
            optimismSepoliaToken
        );
    }
}
