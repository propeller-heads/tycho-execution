// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./StablePool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/forge-std/src/console.sol";
import {ReentrancyGuard} from
    "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Contract is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Unauthorized();

    constructor() {}

    function whoIsThis() public view returns (address) {
        return address(this);
    }

    function execute(
        uint256 amountIn,
        address pool,
        address tokenIn,
        address tokenOut,
        address receiver
    ) public payable nonReentrant returns (uint256 amountOut) {
        require(msg.sender == address(this), Unauthorized());

        IERC20(tokenIn).safeTransfer(pool, amountIn);
        amountOut = StablePool(pool).swap(tokenOut, amountIn, receiver);
    }
}
