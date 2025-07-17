// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../lib/IWETH.sol";
import "../lib/bytes/LibPrefixLengthEncodedByteArray.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@permit2/src/interfaces/IAllowanceTransfer.sol";
import "./Dispatcher.sol";
import {LibSwap} from "../lib/LibSwap.sol";
import {RestrictTransferFrom} from "./RestrictTransferFrom.sol";

error TychoRouter__AddressZero();
error TychoRouter__EmptySwaps();
error TychoRouter__NegativeSlippage(uint256 amount, uint256 minAmount);
error TychoRouter__AmountOutNotFullyReceived(
    uint256 amountIn, uint256 amountConsumed
);
error TychoRouter__MessageValueMismatch(uint256 value, uint256 amount);
error TychoRouter__InvalidDataLength();
error TychoRouter__UndefinedMinAmountOut();

contract TychoRouter is
    AccessControl,
    Dispatcher,
    Pausable,
    ReentrancyGuard,
    RestrictTransferFrom
{
    using SafeERC20 for IERC20;
    using LibPrefixLengthEncodedByteArray for bytes;
    using LibSwap for bytes;

    // this is to keep track of how much a user already inputted into the TychoRouter
    mapping(address owner => mapping(address token => uint256 balance)) public
        balanceOfUser;

    constructor(address _permit2, address weth)
        RestrictTransferFrom(_permit2)
    {
        if (_permit2 == address(0) || weth == address(0)) {
            revert TychoRouter__AddressZero();
        }
        permit2 = IAllowanceTransfer(_permit2);
    }

    function unlock(address token, uint256 amount) public {
        uint256 currentBalance = _balanceOf(token, address(this));
        _unlock(token, currentBalance, amount);
    }

    function singleSwap(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        bool wrapEth,
        bool unwrapEth,
        address receiver,
        bool isTransferFromAllowed,
        bytes calldata swapData
    ) public payable whenNotPaused nonReentrant returns (uint256 amountOut) {
        uint256 initialBalanceTokenOut = _balanceOf(tokenOut, receiver);
        _tstoreTransferFromInfo(tokenIn, amountIn, false, isTransferFromAllowed);

        // handle wrapping

        (address executor, bytes calldata protocolData) =
            swapData.decodeSingleSwap();

        amountOut = _callSwapOnExecutor(executor, amountIn, protocolData);

        if (amountOut < minAmountOut) {
            revert TychoRouter__NegativeSlippage(amountOut, minAmountOut);
        }

        _is_everything_locked_at_the_end();

        // handle unwrapping

        uint256 currentBalanceTokenOut = _balanceOf(tokenOut, receiver);
        if (tokenIn == tokenOut) {
            // If it is an arbitrage, we need to remove the amountIn from the initial balance to get a correct userAmount
            initialBalanceTokenOut -= amountIn;
        }
        uint256 userAmount = currentBalanceTokenOut - initialBalanceTokenOut;
        if (userAmount != amountOut) {
            revert TychoRouter__AmountOutNotFullyReceived(userAmount, amountOut);
        }
    }

    function _balanceOf(address token, address owner)
        internal
        view
        returns (uint256)
    {
        return
            token == address(0) ? owner.balance : IERC20(token).balanceOf(owner);
    }
}
