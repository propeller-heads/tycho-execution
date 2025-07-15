// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@interfaces/IExecutor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@interfaces/ICallback.sol";
import {RestrictTransferFrom} from "../RestrictTransferFrom.sol";
import {ILeverageRouter} from "@interfaces/ILeverageRouter.sol";

error SeamlessExecutor__InvalidDataLength();
error SeamlessExecutor__InvalidLeverageRouter();
error SeamlessExecutor__InvalidTarget();

contract SeamlessExecutor is IExecutor, ICallback, RestrictTransferFrom {
    using SafeERC20 for IERC20;

    uint160 private constant MIN_SQRT_RATIO = 4295128739;
    uint160 private constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    address public immutable leverageRouter;
    address private immutable self;

    constructor(
        address _leverageRouter,
        address _permit2
    ) RestrictTransferFrom(_permit2) {
        if (_leverageRouter == address(0)) {
            revert SeamlessExecutor__InvalidLeverageRouter();
        }
        leverageRouter = _leverageRouter;
        self = address(this);
    }

    // slither-disable-next-line locked-ether
    function swap(
        uint256 amountIn,
        bytes calldata data
    ) external payable returns (uint256 amountOut) {
        (
            address tokenIn,
            address tokenOut,
            uint24 fee,
            address receiver,
            address target,
            bool zeroForOne,
            TransferType transferType
        ) = _decodeData(data);

        _verifyPairAddress(tokenIn, tokenOut, fee, target);

        ILeverageRouter(leverageRouter).mint(
            ILeverageToken(target),
            amountIn,
            0,
            0,
            ISwapAdapter.SwapContext()
        );
    }

    function handleCallback(
        bytes calldata msgData
    ) public returns (bytes memory result) {
        return abi.encode(amountOwed, tokenIn);
    }

    function verifyCallback(bytes calldata data) public view {
        address tokenIn = address(bytes20(data[0:20]));
        address tokenOut = address(bytes20(data[20:40]));
        uint24 poolFee = uint24(bytes3(data[40:43]));

        _verifyPairAddress(tokenIn, tokenOut, poolFee, msg.sender);
    }

    function uniswapV3SwapCallback(
        int256 /* amount0Delta */,
        int256 /* amount1Delta */,
        bytes calldata /* data */
    ) external {
        handleCallback(msg.data);
    }

    function _decodeData(
        bytes calldata data
    )
        internal
        pure
        returns (
            address tokenIn,
            address tokenOut,
            uint24 fee,
            address receiver,
            address target,
            bool zeroForOne,
            TransferType transferType
        )
    {
        if (data.length != 85) {
            revert UniswapV3Executor__InvalidDataLength();
        }
        tokenIn = address(bytes20(data[0:20]));
        tokenOut = address(bytes20(data[20:40]));
        fee = uint24(bytes3(data[40:43]));
        receiver = address(bytes20(data[43:63]));
        target = address(bytes20(data[63:83]));
        zeroForOne = uint8(data[83]) > 0;
        transferType = TransferType(uint8(data[84]));
    }
}
