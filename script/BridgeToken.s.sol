// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract BridgeToken is Script {
    function run(
        address _routerAddress,
        uint64 _destinationChainSelector,
        address _reciever,
        address _token,
        uint256 _amount,
        address _linkTokenAddress
    ) public {
        vm.startBroadcast();
        Client.EVM2AnyMessage memory message = _buildCCIPMessage(_reciever, _token, _amount, _linkTokenAddress);
        uint256 fees = IRouterClient(_routerAddress).getFee(_destinationChainSelector, message);
        IERC20(_linkTokenAddress).approve(_routerAddress, fees);
        IERC20(_token).approve(_routerAddress, _amount);
        IRouterClient(_routerAddress).ccipSend(_destinationChainSelector, message);
        vm.stopBroadcast();
    }

    function _buildCCIPMessage(address _receiver, address _token, uint256 _amount, address _feeTokenAddress)
        private
        pure
        returns (Client.EVM2AnyMessage memory)
    {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: _token, amount: _amount});

        return Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: true})), // we don't have ccipRecieve function so no gasLimit
            feeToken: _feeTokenAddress
        });
    }
}
