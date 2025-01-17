// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "permit2/src/interfaces/IAllowanceTransfer.sol";

contract TychoRouter {
    IAllowanceTransfer public immutable permit2;
    constructor(address _permit2) {
        permit2 = IAllowanceTransfer(_permit2);
    }

    //keccak256("EXECUTOR_ROLE") : save gas on deployment
    bytes32 public constant EXECUTOR_ROLE =
        0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63;

    // TODO add roles - this executor role should be called EXECUTOR_SETTER_ROLE

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev We use the fallback function to allow flexibility on callback.
     * This function will delegate call a verifier contract and should revert is the caller is not a pool.
     */
    fallback() external {
        // TODO execute generic callback
    }

    /**
     * @dev Executes a swap graph with internal splits token amount
     *  splits, checking that the user gets more than minUserAmount of buyToken.
     *
     *  Assumes the swaps in swaps_ already contain any required token
     *  addresses.
     */
    function splitExactIn(
        uint256 amountIn,
        address tokenIn,
        uint256 minUserAmount,
        bool wrapEth,
        bool UnwrapEth,
        SplitSwapExactInParameters calldata parameters
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature
    )
        external
        override
        returns (uint256 amountOut)
    {
        // TODO
    }

    /**
     * @dev We use the fallback function to allow flexibility on callback.
     */
    fallback() external {
        // TODO
    }

    /**
     * @dev Allows granting roles to multiple accounts in a single call.
     */
    function batchGrantRole(bytes32 role, address[] memory accounts)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            _grantRole(role, accounts[i]);
        }
    }

    /**
     * @dev Allows this contract to receive native token
     */
    receive() external payable {}


}
