// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@interfaces/IExecutor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap-v2/contracts/interfaces/IUniswapV2Pair.sol";

error UniswapV2Executor__InvalidDataLength();

contract UniswapV2Executor is IExecutor {
    using SafeERC20 for IERC20;

    // slither-disable-next-line locked-ether
    function swap(uint256 givenAmount, bytes calldata data)
        external
        payable
        returns (uint256 calculatedAmount)
    {
        address target;
        address receiver;
        bool zeroForOne;
        IERC20 tokenIn;

        (tokenIn, target, receiver, zeroForOne) = _decodeData(data);
        calculatedAmount = _getAmountOut(target, givenAmount, zeroForOne);
        tokenIn.safeTransfer(target, givenAmount);

        IUniswapV2Pair pool = IUniswapV2Pair(target);
        if (zeroForOne) {
            pool.swap(0, calculatedAmount, receiver, "");
        } else {
            pool.swap(calculatedAmount, 0, receiver, "");
        }
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (
            IERC20 inToken,
            address target,
            address receiver,
            bool zeroForOne
        )
    {
        if (data.length != 61) {
            revert UniswapV2Executor__InvalidDataLength();
        }
        inToken = IERC20(address(bytes20(data[0:20])));
        target = address(bytes20(data[20:40]));
        receiver = address(bytes20(data[40:60]));
        zeroForOne = uint8(data[60]) > 0;
    }

    function _getAmountOut(address target, uint256 amountIn, bool zeroForOne)
        internal
        view
        returns (uint256 amount)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(target);
        uint112 reserveIn;
        uint112 reserveOut;
        if (zeroForOne) {
            // slither-disable-next-line unused-return
            (reserveIn, reserveOut,) = pair.getReserves();
        } else {
            // slither-disable-next-line unused-return
            (reserveOut, reserveIn,) = pair.getReserves();
        }

        require(reserveIn > 0 && reserveOut > 0, "L");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * uint256(reserveOut);
        uint256 denominator = (uint256(reserveIn) * 1000) + amountInWithFee;
        amount = numerator / denominator;
    }
}
