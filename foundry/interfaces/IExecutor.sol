// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@permit2/src/interfaces/ISignatureTransfer.sol";

pragma abicoder v2;

interface IExecutor {
    /**
     * @notice Performs a swap on a liquidity pool.
     * @dev This method takes the amount of the input token and returns the amount of
     * the output token which has been swapped.
     *
     * Note Part of the informal interface is that the executor supports sending the received
     *  tokens to a receiver address. If the underlying smart contract does not provide this
     *  functionality consider adding an additional transfer in the implementation.
     *
     * @param givenAmount The amount of the input token to swap.
     * @param data Data that holds information necessary to perform the swap.
     * @return calculatedAmount The amount of the output token swapped, depending on
     * the givenAmount inputted.
     */
    function swap(
        uint256 givenAmount,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature,
        bytes calldata data
    ) external payable returns (uint256 calculatedAmount);
}

interface IExecutorErrors {
    error InvalidParameterLength(uint256);
    error UnknownPoolType(uint8);
}
