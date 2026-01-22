// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IExecutor} from "@interfaces/IExecutor.sol";
import {ICallback} from "@interfaces/ICallback.sol";
import {ICore} from "@ekubo-v3/interfaces/ICore.sol";
import {IFlashAccountant} from "@ekubo-v3/interfaces/IFlashAccountant.sol";
import {CoreLib} from "@ekubo-v3/libraries/CoreLib.sol";
import {FlashAccountantLib} from "@ekubo-v3/libraries/FlashAccountantLib.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {LibBytes} from "@solady/utils/LibBytes.sol";
import {LibCall} from "@solady/utils/LibCall.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {
    SqrtRatio,
    MIN_SQRT_RATIO,
    MAX_SQRT_RATIO
} from "@ekubo-v3/types/sqrtRatio.sol";
import {RestrictTransferFrom} from "../RestrictTransferFrom.sol";
import {BaseLocker} from "@ekubo-v3/base/BaseLocker.sol";
import {PoolKey} from "@ekubo-v3/types/poolKey.sol";
import {NATIVE_TOKEN_ADDRESS} from "@ekubo-v3/math/constants.sol";
import {PoolConfig} from "@ekubo-v3/types/poolConfig.sol";
import {PoolBalanceUpdate} from "@ekubo-v3/types/poolBalanceUpdate.sol";
import {PoolState} from "@ekubo-v3/types/poolState.sol";
import {
    createSwapParameters,
    SwapParameters
} from "@ekubo-v3/types/swapParameters.sol";

using CoreLib for ICore;
using FlashAccountantLib for ICore;

address payable constant CORE_ADDRESS =
    payable(0x00000000000014aA86C5d3c41765bb24e11bd701);
ICore constant CORE = ICore(CORE_ADDRESS);
address constant MEV_CAPTURE_ADDRESS =
    0x5555fF9Ff2757500BF4EE020DcfD0210CFfa41Be;

contract EkuboV3Executor is IExecutor, ICallback, RestrictTransferFrom {
    error EkuboExecutor__InvalidDataLength();
    error EkuboExecutor__CoreOnly();
    error EkuboExecutor__UnknownCallback();

    uint256 constant POOL_DATA_OFFSET = 57;
    uint256 constant HOP_BYTE_LEN = 52;

    bytes4 constant LOCKED_SELECTOR = 0x00000000; // cast sig "locked_6416899205(uint256)"

    uint256 constant SKIP_AHEAD = 0;

    using SafeERC20 for IERC20;

    constructor(address _permit2) RestrictTransferFrom(_permit2) {}

    modifier coreOnly() {
        if (msg.sender != CORE_ADDRESS) revert EkuboExecutor__CoreOnly();
        _;
    }

    function swap(uint256 amountIn, bytes calldata data)
        external
        payable
        returns (uint256 calculatedAmount)
    {
        if (data.length < 92) revert EkuboExecutor__InvalidDataLength();

        // amountIn must be at most type(int128).MAX
        calculatedAmount = uint256(
            _lock(
                bytes.concat(
                    bytes16(uint128(SafeCastLib.toInt128(amountIn))), data
                )
            )
        );
    }

    function handleCallback(bytes calldata raw) public returns (bytes memory) {
        verifyCallback(raw);

        // Without selector and locker id
        bytes calldata stripped = raw[36:];

        return abi.encode(_locked(stripped));
    }

    function verifyCallback(bytes calldata raw) public view coreOnly {
        bytes4 selector = bytes4(raw[:4]);
        if (selector != LOCKED_SELECTOR) {
            revert EkuboExecutor__UnknownCallback();
        }
    }

    function _lock(bytes memory data) private returns (uint128 swappedAmount) {
        bytes memory result = LibCall.callContract(
            CORE_ADDRESS, abi.encodePacked(IFlashAccountant.lock.selector, data)
        );
        swappedAmount = abi.decode(result, (uint128));
    }

    function _locked(bytes calldata swapData) private returns (uint128) {
        uint128 amountIn = uint128(bytes16(swapData[0:16]));
        int128 nextAmountIn = int128(amountIn);
        TransferType transferType = TransferType(uint8(swapData[16]));
        address receiver = address(bytes20(swapData[17:37]));
        address tokenIn = address(bytes20(swapData[37:57]));

        address nextTokenIn = tokenIn;

        uint256 hopsLength = (swapData.length - POOL_DATA_OFFSET) / HOP_BYTE_LEN;

        uint256 offset = POOL_DATA_OFFSET;

        for (uint256 i = 0; i < hopsLength; i++) {
            address nextTokenOut =
                address(bytes20(LibBytes.loadCalldata(swapData, offset)));
            PoolConfig poolConfig =
                PoolConfig.wrap(LibBytes.loadCalldata(swapData, offset + 20));

            (
                address token0,
                address token1,
                bool isToken1,
                SqrtRatio sqrtRatioLimit
            ) = nextTokenIn > nextTokenOut
                ? (nextTokenOut, nextTokenIn, true, MAX_SQRT_RATIO)
                : (nextTokenIn, nextTokenOut, false, MIN_SQRT_RATIO);

            PoolKey memory pk =
                PoolKey({token0: token0, token1: token1, config: poolConfig});

            SwapParameters swapParameters = createSwapParameters({
                _sqrtRatioLimit: sqrtRatioLimit,
                _amount: nextAmountIn,
                _isToken1: isToken1,
                _skipAhead: SKIP_AHEAD
            });

            PoolBalanceUpdate balanceUpdate;

            if (poolConfig.extension() == MEV_CAPTURE_ADDRESS) {
                (balanceUpdate,) = abi.decode(
                    // slither-disable-next-line calls-loop
                    CORE.forward(
                        MEV_CAPTURE_ADDRESS, abi.encode(pk, swapParameters)
                    ),
                    (PoolBalanceUpdate, PoolState)
                );
            } else {
                // slither-disable-next-line calls-loop
                (balanceUpdate,) = CORE.swap(0, pk, swapParameters);
            }

            nextTokenIn = nextTokenOut;
            nextAmountIn =
            -(isToken1 ? balanceUpdate.delta0() : balanceUpdate.delta1());

            offset += HOP_BYTE_LEN;
        }

        // Only exact-in swaps are supported, so this is always non-negative
        uint128 amountOut = uint128(nextAmountIn);

        _pay(tokenIn, amountIn, transferType);
        CORE.withdraw(nextTokenIn, receiver, amountOut);

        return amountOut;
    }

    function _pay(address token, uint128 amount, TransferType transferType)
        private
    {
        if (token == NATIVE_TOKEN_ADDRESS) {
            SafeTransferLib.safeTransferETH(CORE_ADDRESS, amount);
            return;
        }

        LibCall.callContract(
            CORE_ADDRESS,
            abi.encodeWithSelector(
                IFlashAccountant.startPayments.selector, token
            )
        );

        _transfer(CORE_ADDRESS, transferType, token, amount);

        LibCall.callContract(
            CORE_ADDRESS,
            abi.encodeWithSelector(
                IFlashAccountant.completePayments.selector, token
            )
        );
    }
}
