// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IExecutor} from "@interfaces/IExecutor.sol";
import {ICallback} from "@interfaces/ICallback.sol";
import {ICore} from "@ekubo/interfaces/ICore.sol";
import {ILocker, IPayer} from "@ekubo/interfaces/IFlashAccountant.sol";
import {NATIVE_TOKEN_ADDRESS} from "@ekubo/math/constants.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {LibBytes} from "@solady/utils/LibBytes.sol";
import {Config, PoolKey} from "@ekubo/types/poolKey.sol";
import {
    MAX_SQRT_RATIO,
    MIN_SQRT_RATIO,
    SqrtRatio
} from "@ekubo/types/sqrtRatio.sol";
import {RestrictTransferFrom} from "../RestrictTransferFrom.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract EkuboExecutor is
    IExecutor,
    ILocker,
    IPayer,
    ICallback,
    RestrictTransferFrom
{
    error EkuboExecutor__AddressZero();
    error EkuboExecutor__InvalidDataLength();
    error EkuboExecutor__CoreOnly();
    error EkuboExecutor__UnknownCallback();

    ICore immutable core;
    address immutable mevResist;

    uint256 constant POOL_DATA_OFFSET = 57;
    uint256 constant HOP_BYTE_LEN = 52;

    bytes4 constant LOCKED_SELECTOR = 0xb45a3c0e; // locked(uint256)
    bytes4 constant PAY_CALLBACK_SELECTOR = 0x599d0714; // payCallback(uint256,address)

    uint256 constant SKIP_AHEAD = 0;

    using SafeERC20 for IERC20;

    constructor(address _core, address _mevResist, address _permit2)
        RestrictTransferFrom(_permit2)
    {
        core = ICore(_core);

        if (_mevResist == address(0)) {
            revert EkuboExecutor__AddressZero();
        }
        mevResist = _mevResist;
    }

    function swap(uint256 amountIn, bytes calldata data)
        external
        payable
        returns (uint256 calculatedAmount)
    {
        if (data.length < 92) revert EkuboExecutor__InvalidDataLength();

        // amountIn must be at most type(int128).MAX
        calculatedAmount =
            uint256(_lock(bytes.concat(bytes16(uint128(amountIn)), data)));
    }

    function handleCallback(bytes calldata raw)
        external
        returns (bytes memory)
    {
        verifyCallback(raw);

        // Without selector and locker id
        bytes calldata stripped = raw[36:];

        bytes4 selector = bytes4(raw[:4]);

        bytes memory result = "";
        if (selector == LOCKED_SELECTOR) {
            int128 calculatedAmount = _locked(stripped);
            result = abi.encodePacked(calculatedAmount);
        } else if (selector == PAY_CALLBACK_SELECTOR) {
            _payCallback(stripped);
        } else {
            revert EkuboExecutor__UnknownCallback();
        }

        return result;
    }

    function verifyCallback(bytes calldata) public view coreOnly {}

    function locked(uint256) external coreOnly {
        // Without selector and locker id
        int128 calculatedAmount = _locked(msg.data[36:]);
        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            mstore(0, calculatedAmount)
            return(0x10, 16)
        }
    }

    function payCallback(
        uint256,
        address /*token*/
    )
        external
        coreOnly
    {
        // Without selector and locker id
        _payCallback(msg.data[36:]);
    }

    function _lock(bytes memory data) internal returns (uint128 swappedAmount) {
        address target = address(core);

        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            let args := mload(0x40)

            // Selector of lock()
            mstore(args, shl(224, 0xf83d08ba))

            // We only copy the data, not the length, because the length is read from the calldata size
            let len := mload(data)
            mcopy(add(args, 4), add(data, 32), len)

            // If the call failed, pass through the revert
            if iszero(call(gas(), target, 0, args, add(len, 36), 0, 0)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            returndatacopy(0, 0, 16)
            swappedAmount := shr(128, mload(0))
        }
    }

    function _locked(bytes calldata swapData) internal returns (int128) {
        int128 nextAmountIn = int128(uint128(bytes16(swapData[0:16])));
        uint128 tokenInDebtAmount = uint128(nextAmountIn);
        TransferType transferType = TransferType(uint8(swapData[16]));
        address receiver = address(bytes20(swapData[17:37]));
        address tokenIn = address(bytes20(swapData[37:57]));

        address nextTokenIn = tokenIn;

        uint256 hopsLength = (swapData.length - POOL_DATA_OFFSET) / HOP_BYTE_LEN;

        uint256 offset = POOL_DATA_OFFSET;

        for (uint256 i = 0; i < hopsLength; i++) {
            address nextTokenOut =
                address(bytes20(LibBytes.loadCalldata(swapData, offset)));
            Config poolConfig =
                Config.wrap(LibBytes.loadCalldata(swapData, offset + 20));

            (
                address token0,
                address token1,
                bool isToken1,
                SqrtRatio sqrtRatioLimit
            ) = nextTokenIn > nextTokenOut
                ? (nextTokenOut, nextTokenIn, true, MAX_SQRT_RATIO)
                : (nextTokenIn, nextTokenOut, false, MIN_SQRT_RATIO);

            PoolKey memory pk = PoolKey(token0, token1, poolConfig);

            int128 delta0;
            int128 delta1;

            if (poolConfig.extension() == mevResist) {
                (delta0, delta1) = abi.decode(
                    _forward(
                        mevResist,
                        abi.encode(
                            pk,
                            nextAmountIn,
                            isToken1,
                            sqrtRatioLimit,
                            SKIP_AHEAD
                        )
                    ),
                    (int128, int128)
                );
            } else {
                // slither-disable-next-line calls-loop
                (delta0, delta1) = core.swap_611415377(
                    pk, nextAmountIn, isToken1, sqrtRatioLimit, SKIP_AHEAD
                );
            }

            nextTokenIn = nextTokenOut;
            nextAmountIn = -(isToken1 ? delta0 : delta1);

            offset += HOP_BYTE_LEN;
        }

        _pay(tokenIn, tokenInDebtAmount, transferType);
        core.withdraw(nextTokenIn, receiver, uint128(nextAmountIn));
        return nextAmountIn;
    }

    function _forward(address to, bytes memory data)
        internal
        returns (bytes memory result)
    {
        address target = address(core);

        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            // We will store result where the free memory pointer is now, ...
            result := mload(0x40)

            // But first use it to store the calldata

            // Selector of forward(address)
            mstore(result, shl(224, 0x101e8952))
            mstore(add(result, 4), to)

            // We only copy the data, not the length, because the length is read from the calldata size
            let len := mload(data)
            mcopy(add(result, 36), add(data, 32), len)

            // If the call failed, pass through the revert
            if iszero(call(gas(), target, 0, result, add(36, len), 0, 0)) {
                returndatacopy(result, 0, returndatasize())
                revert(result, returndatasize())
            }

            // Copy the entire return data into the space where the result is pointing
            mstore(result, returndatasize())
            returndatacopy(add(result, 32), 0, returndatasize())

            // Update the free memory pointer to be after the end of the data, aligned to the next 32 byte word
            mstore(
                0x40,
                and(add(add(result, add(32, returndatasize())), 31), not(31))
            )
        }
    }

    function _pay(address token, uint128 amount, TransferType transferType)
        internal
    {
        address target = address(core);

        if (token == NATIVE_TOKEN_ADDRESS) {
            SafeTransferLib.safeTransferETH(target, amount);
        } else {
            // slither-disable-next-line assembly
            assembly ("memory-safe") {
                let free := mload(0x40)
                // selector of pay(address)
                mstore(free, shl(224, 0x0c11dedd))
                mstore(add(free, 4), token)
                mstore(add(free, 36), shl(128, amount))
                mstore(add(free, 52), shl(248, transferType))

                // 4 (selector) + 32 (token) + 16 (amount) + 1 (transferType) = 53
                if iszero(call(gas(), target, 0, free, 53, 0, 0)) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
        }
    }

    function _payCallback(bytes calldata payData) internal {
        address token = address(bytes20(payData[12:32])); // This arg is abi-encoded
        uint128 amount = uint128(bytes16(payData[32:48]));
        TransferType transferType = TransferType(uint8(payData[48]));
        _transfer(address(core), transferType, token, amount);
    }

    // To receive withdrawals from Core
    receive() external payable {}

    modifier coreOnly() {
        if (msg.sender != address(core)) revert EkuboExecutor__CoreOnly();
        _;
    }
}
