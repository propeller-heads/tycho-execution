// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@interfaces/IExecutor.sol";
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    SwapKind,
    VaultSwapParams,
    BufferWrapOrUnwrapParams,
    WrappingDirection
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {RestrictTransferFrom} from "../RestrictTransferFrom.sol";
import {ICallback} from "@interfaces/ICallback.sol";

error BalancerV3Executor__InvalidDataLength();
error BalancerV3Executor__SenderIsNotVault(address sender);

contract BalancerV3Executor is IExecutor, RestrictTransferFrom, ICallback {
    using SafeERC20 for IERC20;

    IVault private constant VAULT =
        IVault(0xbA1333333333a1BA1108E8412f11850A5C319bA9);

    constructor(address _permit2) RestrictTransferFrom(_permit2) {}

    // slither-disable-next-line locked-ether
    function swap(uint256 givenAmount, bytes calldata data)
        external
        payable
        returns (uint256 calculatedAmount)
    {
        if (data.length != 121) {
            revert BalancerV3Executor__InvalidDataLength();
        }
        bytes memory result = VAULT.unlock(
            abi.encodeCall(
                BalancerV3Executor.swapCallback,
                abi.encodePacked(givenAmount, data)
            )
        );
        calculatedAmount = abi.decode(abi.decode(result, (bytes)), (uint256));
    }

    function verifyCallback(bytes calldata /*data*/ ) public view {
        if (msg.sender != address(VAULT)) {
            revert BalancerV3Executor__SenderIsNotVault(msg.sender);
        }
    }

    function _swapCallback(bytes calldata data)
        internal
        returns (bytes memory result)
    {
        verifyCallback(data);
        (
            uint256 amountGiven,
            IERC20 tokenIn,
            IERC20 tokenOut,
            address poolId,
            TransferType transferType,
            bool wrapIn,
            bool unwrapIn,
            bool wrapOut,
            bool unwrapOut,
            address wrappedTokenIn,
            address wrappedTokenOut,
            address receiver
        ) = _decodeData(data);

        IERC20 swapTokenIn = tokenIn;
        IERC20 swapTokenOut = tokenOut;
        uint256 amountIn = 0;
        uint256 amountOut = 0;
        uint256 amountCalculated = 0;
        uint256 swapExactAmountIn = amountGiven;

        // 1. Pre-processing (wrapIn / unwrapIn)
        if (wrapIn) {
            // ERC20 -> ERC4626
            (uint256 wrappedOut, uint256 wrapAmountInRaw,) = VAULT
                .erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.WRAP,
                    wrappedToken: IERC4626(wrappedTokenIn),
                    amountGivenRaw: amountGiven,
                    limitRaw: 0
                })
            );
            swapTokenIn = IERC20(wrappedTokenIn);
            swapExactAmountIn = wrappedOut;
            amountIn = wrapAmountInRaw;
        } else if (unwrapIn) {
            // ERC4626 -> ERC20
            (uint256 unwrappedOut, uint256 unwrapAmountInRaw,) = VAULT
                .erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.UNWRAP,
                    wrappedToken: IERC4626(wrappedTokenIn),
                    amountGivenRaw: amountGiven,
                    limitRaw: 0
                })
            );
            swapTokenIn = IERC20(IERC4626(wrappedTokenIn).asset()); // todo how to get underlying?
            swapExactAmountIn = unwrappedOut;
            amountIn = unwrapAmountInRaw;
        } else {
            amountIn = amountGiven;
        }

        if (wrapOut) {
            swapTokenOut = IERC20(IERC4626(wrappedTokenOut).asset());
        } else if (unwrapOut) {
            swapTokenOut = IERC20(wrappedTokenOut);
        }

        // 2. Pool Swap
        (
            uint256 swapAmountCalculated,
            uint256 swapAmountIn,
            uint256 swapAmountOut
        ) = VAULT.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: poolId,
                tokenIn: swapTokenIn,
                tokenOut: swapTokenOut,
                amountGivenRaw: swapExactAmountIn,
                limitRaw: 0,
                userData: ""
            })
        );

        amountCalculated = swapAmountCalculated;

        // todo need to delete?
        if (amountIn == 0 && swapAmountIn > 0) {
            amountIn = swapAmountIn;
        }

        // 3. Post-processing (wrapOut / unwrapOut)
        if (wrapOut) {
            // ERC20 -> ERC4626
            (uint256 wrappedOut,,) = VAULT.erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.WRAP,
                    wrappedToken: IERC4626(wrappedTokenOut),
                    amountGivenRaw: swapAmountCalculated,
                    limitRaw: 0
                })
            );
            amountCalculated = wrappedOut;
            amountOut = wrappedOut;
        } else if (unwrapOut) {
            // ERC4626 -> ERC20
            (uint256 unwrappedOut,,) = VAULT.erc4626BufferWrapOrUnwrap(
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.UNWRAP,
                    wrappedToken: IERC4626(wrappedTokenOut),
                    amountGivenRaw: swapAmountCalculated,
                    limitRaw: 0
                })
            );
            amountCalculated = unwrappedOut;
            amountOut = unwrappedOut;
        } else {
            amountOut = swapAmountOut;
        }

        // 4. Final settle + sendTo
        _transfer(address(VAULT), transferType, address(tokenIn), amountIn);
        VAULT.settle(tokenIn, amountIn);
        VAULT.sendTo(tokenOut, receiver, amountOut);

        return abi.encode(amountCalculated);
    }

    function handleCallback(bytes calldata data)
        external
        returns (bytes memory result)
    {
        verifyCallback(data);
        // Remove the first 68 bytes (4 selector + 32 dataOffset + 32 dataLength) and extract 153 bytes (32 givenAmount + 121 executor data)
        result = _swapCallback(data[68:221]);
        // Our general callback logic returns a not ABI encoded result (see Dispatcher._callHandleCallbackOnExecutor).
        // However, the Vault expects the result to be ABI encoded. That is why we need to encode it here again.
        return abi.encode(result);
    }

    function swapCallback(bytes calldata data)
        external
        returns (bytes memory result)
    {
        return _swapCallback(data);
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (
            uint256 amountGiven,
            IERC20 tokenIn,
            IERC20 tokenOut,
            address poolId,
            TransferType transferType,
            bool wrapIn,
            bool unwrapIn,
            bool wrapOut,
            bool unwrapOut,
            address wrappedTokenIn,
            address wrappedTokenOut,
            address receiver
        )
    {
        amountGiven = uint256(bytes32(data[0:32]));
        tokenIn = IERC20(address(bytes20(data[32:52])));
        tokenOut = IERC20(address(bytes20(data[52:72])));
        poolId = address(bytes20(data[72:92]));
        uint8 packed = uint8(data[92]);
        wrapIn = (packed & 1) != 0; // bit0
        unwrapIn = ((packed >> 1) & 1) != 0; // bit1
        wrapOut = ((packed >> 2) & 1) != 0; // bit2
        unwrapOut = ((packed >> 3) & 1) != 0; // bit3
        transferType = TransferType(packed >> 4);
        wrappedTokenIn = address(bytes20(data[93:113]));
        wrappedTokenOut = address(bytes20(data[113:133]));
        receiver = address(bytes20(data[133:153]));
    }
}
