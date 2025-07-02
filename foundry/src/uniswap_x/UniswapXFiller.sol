// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./IReactor.sol";
import "./IReactorCallback.sol";
import {
    SafeERC20,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";

error UniswapXFiller__AddressZero();

contract UniswapXFiller is AccessControl, IReactorCallback {
    using SafeERC20 for IERC20;
    // Uniswap X V2DutchOrder Reactor

    IReactor public constant USXEDAReactor =
        IReactor(0x00000011F84B9aa48e5f8aA8B9897600006289Be);
    address public tychoRouter;

    event Withdrawal(
        address indexed token, uint256 amount, address indexed receiver
    );

    constructor(address _tychoRouter) {
        tychoRouter = _tychoRouter;
    }

    // TODO: setup roles for filler

    function execute(SignedOrder calldata order, bytes calldata callbackData)
        external
    {
        USXEDAReactor.executeWithCallback(order, callbackData);
    }

    function reactorCallback(
        ResolvedOrder[] calldata resolvedOrders,
        bytes calldata callbackData
    ) external {
        // we only support one order at a time (no batch execution)
        ResolvedOrder memory order = resolvedOrders[0];

        uint256 ethValue = 0;
        if (order.input.token != address(0)) {
            IERC20(order.input.token).safeTransfer(
                address(tychoRouter), order.input.amount
            );
        } else {
            ethValue = order.input.amount;
        }
        (bool success, bytes memory result) =
            tychoRouter.call{value: ethValue}(callbackData);

        // assumes one output token
        // TODO: be better here
        IERC20 token = IERC20(order.outputs[0].token);
        token.forceApprove(address(USXEDAReactor), type(uint256).max);
    }

    /**
     * @dev Allows granting roles to multiple accounts in a single call.
     */
    function batchGrantRole(bytes32 role, address[] memory accounts)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            _grantRole(role, accounts[i]);
        }
    }

    /**
     * @dev Allows withdrawing any ERC20 funds if funds get stuck in case of a bug.
     */
    function withdraw(IERC20[] memory tokens, address receiver)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (receiver == address(0)) revert UniswapXFiller__AddressZero();

        for (uint256 i = 0; i < tokens.length; i++) {
            // slither-disable-next-line calls-loop
            uint256 tokenBalance = tokens[i].balanceOf(address(this));
            if (tokenBalance > 0) {
                emit Withdrawal(address(tokens[i]), tokenBalance, receiver);
                tokens[i].safeTransfer(receiver, tokenBalance);
            }
        }
    }

    /**
     * @dev Allows withdrawing any NATIVE funds if funds get stuck in case of a bug.
     * The contract should never hold any NATIVE tokens for security reasons.
     */
    function withdrawNative(address receiver)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (receiver == address(0)) revert UniswapXFiller__AddressZero();

        uint256 amount = address(this).balance;
        if (amount > 0) {
            emit Withdrawal(address(0), amount, receiver);
            Address.sendValue(payable(receiver), amount);
        }
    }

    /**
     * @dev Allows this contract to receive native token with empty msg.data from contracts
     */
    receive() external payable {
        require(msg.sender.code.length != 0);
    }
}
