// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@interfaces/IExecutor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract EulerSwapExecutor is IExecutor {
    using SafeERC20 for IERC20;

    address public immutable periphery;

    error EulerSwapExecutor__InvalidDataLength();
    error EulerSwapExecutor__InvalidPeriphery();

    constructor(address _periphery) {
        require(_periphery != address(0), EulerSwapExecutor__InvalidPeriphery());

        periphery = _periphery;
    }

    // slither-disable-next-line locked-ether
    function swap(uint256 givenAmount, bytes calldata data)
        external
        payable
        returns (uint256 calculatedAmount)
    {
        address target;
        address receiver;
        IERC20 tokenIn;
        IERC20 tokenOut;
        (tokenIn, tokenOut, target, receiver) = _decodeData(data);

        calculatedAmount = IEulerSwapPeriphery(periphery).quoteExactInput(
            target, address(tokenIn), address(tokenOut), givenAmount
        );
        tokenIn.safeTransfer(target, givenAmount);

        bool isAsset0In = tokenIn < tokenOut;
        (isAsset0In)
            ? IEulerSwap(target).swap(0, calculatedAmount, receiver, "")
            : IEulerSwap(target).swap(calculatedAmount, 0, receiver, "");
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (
            IERC20 inToken,
            IERC20 outToken,
            address target,
            address receiver
        )
    {
        require(data.length == 80, EulerSwapExecutor__InvalidDataLength());

        inToken = IERC20(address(bytes20(data[0:20])));
        outToken = IERC20(address(bytes20(data[20:40])));
        target = address(bytes20(data[40:60]));
        receiver = address(bytes20(data[60:80]));
    }
}

interface IEulerSwap {
    struct Params {
        address vault0;
        address vault1;
        address eulerAccount;
        uint112 equilibriumReserve0;
        uint112 equilibriumReserve1;
        uint112 currReserve0;
        uint112 currReserve1;
        uint256 fee;
    }

    struct CurveParams {
        uint256 priceX;
        uint256 priceY;
        uint256 concentrationX;
        uint256 concentrationY;
    }

    /// @notice Optimistically sends the requested amounts of tokens to the `to`
    /// address, invokes `uniswapV2Call` callback on `to` (if `data` was provided),
    /// and then verifies that a sufficient amount of tokens were transferred to
    /// satisfy the swapping curve invariant.
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /// @notice Approves the vaults to access the EulerSwap instance's tokens, and enables
    /// vaults as collateral. Can be invoked by anybody, and is harmless if invoked again.
    /// Calling this function is optional: EulerSwap can be activated on the first swap.
    function activate() external;

    /// @notice Function that defines the shape of the swapping curve. Returns true iff
    /// the specified reserve amounts would be acceptable (ie it is above and to-the-right
    /// of the swapping curve).
    function verify(uint256 newReserve0, uint256 newReserve1)
        external
        view
        returns (bool);

    /// @notice Returns the address of the Ethereum Vault Connector (EVC) used by this contract.
    /// @return The address of the EVC contract.
    function EVC() external view returns (address);

    // EulerSwap Accessors

    function curve() external view returns (bytes32);
    function vault0() external view returns (address);
    function vault1() external view returns (address);
    function asset0() external view returns (address);
    function asset1() external view returns (address);
    function eulerAccount() external view returns (address);
    function equilibriumReserve0() external view returns (uint112);
    function equilibriumReserve1() external view returns (uint112);
    function feeMultiplier() external view returns (uint256);
    /// @notice Returns the current reserves of the pool
    /// @return reserve0 The amount of asset0 in the pool
    /// @return reserve1 The amount of asset1 in the pool
    /// @return status The status of the pool (0 = unactivated, 1 = unlocked, 2 = locked)
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 status);

    // Curve Accessors

    function priceX() external view returns (uint256);
    function priceY() external view returns (uint256);
    function concentrationX() external view returns (uint256);
    function concentrationY() external view returns (uint256);
}

interface IEulerSwapPeriphery {
    /// @notice Swap `amountIn` of `tokenIn` for `tokenOut`, with at least `amountOutMin` received.
    function swapExactIn(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) external;

    /// @notice Swap `amountOut` of `tokenOut` for `tokenIn`, with at most `amountInMax` paid.
    function swapExactOut(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax
    ) external;

    /// @notice How much `tokenOut` can I get for `amountIn` of `tokenIn`?
    function quoteExactInput(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256);

    /// @notice How much `tokenIn` do I need to get `amountOut` of `tokenOut`?
    function quoteExactOutput(
        address eulerSwap,
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256);

    /// @notice Max amount the pool can buy of tokenIn and sell of tokenOut
    function getLimits(address eulerSwap, address tokenIn, address tokenOut)
        external
        view
        returns (uint256, uint256);
}
