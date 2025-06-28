// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./IReactor.sol";
import "./IReactorCallback.sol";
import {
    SafeERC20,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniswapXFiller is IReactorCallback {
    using SafeERC20 for IERC20;
    // Uniswap X V2DutchOrder Reactor

    IReactor public constant USXEDAReactor =
        IReactor(0x00000011F84B9aa48e5f8aA8B9897600006289Be);
    address public tychoRouter;

    constructor(address _tychoRouter) {
        tychoRouter = _tychoRouter;
    }

    // TODO: setup roles for filler

    function execute(SignedOrder calldata order, bytes calldata callbackData)
        external
    {
        USXEDAReactor.executeWithCallback(order, callbackData);
    }

    // TODO: create modifier that only the reactor can call this method

    function reactorCallback(
        ResolvedOrder[] calldata resolvedOrders,
        bytes calldata callbackData
    ) external {
        // TODO: handle ETH
        // TODO: handle approvals with tycho router
        (bool success, bytes memory result) = tychoRouter.call(callbackData);

        // TODO: handle approvals nicely
        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            OutputToken[] calldata outTokens = resolvedOrders[i].outputs;

            IERC20 token = IERC20(outTokens[0].token);
            token.forceApprove(address(USXEDAReactor), type(uint256).max);
        }
    }
}
