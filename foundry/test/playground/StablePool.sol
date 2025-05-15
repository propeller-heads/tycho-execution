// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StablePool {
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
