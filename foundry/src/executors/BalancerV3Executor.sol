pragma solidity ^0.8.26;

import {IExecutor} from "@interfaces/IExecutor.sol";
import {
    IERC20,
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    SwapKind,
    VaultSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {TransferManager} from "../TransferManager.sol";
import {ICallback} from "@interfaces/ICallback.sol";

error BalancerV3Executor__InvalidDataLength();
error BalancerV3Executor__SenderIsNotVault(address sender);

contract BalancerV3Executor is IExecutor, ICallback {
    using SafeERC20 for IERC20;

    IVault private constant _VAULT =
        IVault(0xbA1333333333a1BA1108E8412f11850A5C319bA9);

    constructor() {}

    function fundsExpectedAddress(
        bytes calldata /* data */
    )
        external
        view
        returns (address receiver)
    {
        return msg.sender;
    }

    // slither-disable-next-line locked-ether
    function swap(uint256 amountIn, bytes calldata data, address receiver)
        external
        payable
    {
        if (data.length != 61) {
            revert BalancerV3Executor__InvalidDataLength();
        }
        // slither-disable-next-line unused-return
        _VAULT.unlock(abi.encodePacked(amountIn, data, receiver));
    }

    function verifyCallback(
        bytes calldata /*data*/
    )
        public
        view
    {
        if (msg.sender != address(_VAULT)) {
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
            address receiver
        ) = _decodeData(data);

        uint256 amountCalculated;
        uint256 amountIn;
        uint256 amountOut;
        (amountCalculated, amountIn, amountOut) = _VAULT.swap(
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

        // slither-disable-next-line unused-return
        _VAULT.settle(tokenIn, amountIn);
        _VAULT.sendTo(tokenOut, receiver, amountOut);
        return abi.encode(amountCalculated, tokenOut);
    }

    function handleCallback(bytes calldata data)
        external
        returns (bytes memory result)
    {
        verifyCallback(data);
        result = _swapCallback(data);
        // Our general callback logic returns a not ABI encoded result (see Dispatcher._callHandleCallbackOnExecutor).
        // However, the Vault expects the result to be ABI encoded. That is why we need to encode it here again.
        return abi.encode(result);
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (
            uint256 amountGiven,
            IERC20 tokenIn,
            IERC20 tokenOut,
            address poolId,
            address receiver
        )
    {
        amountGiven = uint256(bytes32(data[0:32]));
        tokenIn = IERC20(address(bytes20(data[32:52])));
        // data[52] is isFeeToken, skipped here
        tokenOut = IERC20(address(bytes20(data[53:73])));
        poolId = address(bytes20(data[73:93]));
        receiver = address(bytes20(data[93:113]));
    }

    function getTransferData(bytes calldata data)
        external
        payable
        returns (
            TransferManager.TransferType transferType,
            address receiver,
            address tokenIn,
            address tokenOut,
            bool outputToRouter,
            bool isFeeToken
        )
    {
        if (data.length >= 41) {
            tokenIn = address(bytes20(data[0:20]));
            isFeeToken = data[20] != 0;
            tokenOut = address(bytes20(data[21:41]));
        }
        return (
            TransferManager.TransferType.None,
            address(0),
            tokenIn,
            tokenOut,
            false,
            isFeeToken
        );
    }

    function getCallbackTransferData(bytes calldata data)
        external
        payable
        returns (
            TransferManager.TransferType transferType,
            address receiver,
            address tokenIn,
            uint256 amount,
            bool isFeeToken
        )
    {
        receiver = address(_VAULT);
        amount = uint256(bytes32(data[0:32]));
        tokenIn = address(bytes20(data[32:52]));
        transferType = TransferManager.TransferType.Transfer;
    }
}
