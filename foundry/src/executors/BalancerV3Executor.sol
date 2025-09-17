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
        if (data.length != 81) {
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
            bool isBuffer,
            bool wrapIn,
            bool unwrapOut,
            address receiver
        ) = _decodeData(data);

        uint256 amountCalculated;
        uint256 amountIn;
        uint256 amountOut;

        if (isBuffer) {
            // Take the token in advance. We need this to wrap/unwrap.
            _transfer(
                address(VAULT), transferType, address(tokenIn), amountGiven
            );
            // slither-disable-next-line unused-return
            VAULT.settle(tokenIn, amountGiven);
            if (wrapIn) {
                // ERC20 -> ERC4626
                (uint256 wrappedOut, uint256 wrapAmountInRaw,) = VAULT
                    .erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: IERC4626(address(tokenOut)),
                        amountGivenRaw: amountGiven,
                        limitRaw: 0
                    })
                );
                amountCalculated = wrappedOut;
                amountIn = wrapAmountInRaw;
                amountOut = wrappedOut;
            } else if (unwrapOut) {
                // ERC4626 -> ERC20
                (uint256 unwrappedOut, uint256 unwrapAmountInRaw,) = VAULT
                    .erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.UNWRAP,
                        wrappedToken: IERC4626(address(tokenIn)),
                        amountGivenRaw: amountGiven,
                        limitRaw: 0
                    })
                );
                amountCalculated = unwrappedOut;
                amountIn = unwrapAmountInRaw;
                amountOut = unwrappedOut;
            }
        } else {
            (amountCalculated, amountIn, amountOut) = VAULT.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_IN,
                    pool: poolId,
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountGivenRaw: amountGiven,
                    limitRaw: 0,
                    userData: ""
                })
            );

            _transfer(address(VAULT), transferType, address(tokenIn), amountIn);
            // slither-disable-next-line unused-return
            VAULT.settle(tokenIn, amountIn);
        }

        VAULT.sendTo(tokenOut, receiver, amountOut);
        return abi.encode(amountCalculated);
    }

    function handleCallback(bytes calldata data)
        external
        returns (bytes memory result)
    {
        verifyCallback(data);
        // Remove the first 68 bytes 4 selector + 32 dataOffset + 32 dataLength and extra padding at the end
        result = _swapCallback(data[68:181]);
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
            bool isBuffer,
            bool wrapIn,
            bool unwrapOut,
            address receiver
        )
    {
        amountGiven = uint256(bytes32(data[0:32]));
        tokenIn = IERC20(address(bytes20(data[32:52])));
        tokenOut = IERC20(address(bytes20(data[52:72])));
        poolId = address(bytes20(data[72:92]));
        uint8 packed = uint8(data[92]);
        isBuffer = (packed & 1) != 0; // bit0
        wrapIn = ((packed >> 1) & 1) != 0; // bit1
        unwrapOut = ((packed >> 2) & 1) != 0; // bit2
        transferType = TransferType(packed >> 3);
        receiver = address(bytes20(data[93:113]));
    }
}
