// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from
    "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/forge-std/src/console.sol";

contract Pool {
    using SafeERC20 for IERC20;

    address public token0;
    address public token1;
    address public pool;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function swap(address tokenOut, uint256 amountIn, address receiver)
        external
        returns (uint256 amountOut)
    {
        IERC20(tokenOut).transfer(receiver, amountIn);
        amountOut = amountIn;
    }
}

contract DelegateContract is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Unauthorized();

    constructor() {}

    function execute(
        uint256 amountIn,
        address pool,
        address tokenIn,
        address tokenOut,
        address receiver
    ) public payable nonReentrant returns (uint256 amountOut) {
        //        require(msg.sender == address(this), Unauthorized()); // access control

        IERC20(tokenIn).safeTransfer(pool, amountIn);
        amountOut = Pool(pool).swap(tokenOut, amountIn, receiver);
    }

    receive() external payable {} // allow receiving ETH
}
