// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "./StablePool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/forge-std/src/console.sol";
import {ReentrancyGuard} from
    "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ContractWithFunds is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Unauthorized();

    constructor() {}

    function whoIsThis() public view returns (address) {
        return address(this);
    }

    function withdraw(address token, uint256 amount, address receiver) public {
        IERC20(token).safeTransfer(receiver, amount);
    }
}
