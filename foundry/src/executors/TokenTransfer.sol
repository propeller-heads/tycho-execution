// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@interfaces/IExecutor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error TokenTransfer__AddressZero();

contract TokenTransfer {
    using SafeERC20 for IERC20;

    function _transfer(
        address tokenIn,
        address receiver,
        uint256 amount,
        bool transferNeeded
    ) internal {
        if (transferNeeded == true) {
            if (tokenIn == address(0)) {
                payable(receiver).transfer(amount);
            } else {
                IERC20(tokenIn).safeTransfer(receiver, amount);
            }
        }
    }
}
