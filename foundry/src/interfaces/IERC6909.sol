// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/**
 * @title IERC6909
 * @dev Interface for the ERC6909 multi-token standard
 * @notice Minimal multi-token interface
 */
interface IERC6909 {
    event Transfer(
        address caller,
        address indexed sender,
        address indexed receiver,
        uint256 indexed id,
        uint256 amount
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id,
        uint256 amount
    );
    event OperatorSet(
        address indexed owner, address indexed spender, bool approved
    );

    function balanceOf(address owner, uint256 id)
        external
        view
        returns (uint256);
    function allowance(address owner, address spender, uint256 id)
        external
        view
        returns (uint256);
    function isOperator(address owner, address spender)
        external
        view
        returns (bool);
    function approve(address spender, uint256 id, uint256 amount)
        external
        returns (bool);
    function setOperator(address spender, bool approved) external returns (bool);
    function transfer(address receiver, uint256 id, uint256 amount)
        external
        returns (bool);
    function transferFrom(
        address sender,
        address receiver,
        uint256 id,
        uint256 amount
    ) external returns (bool);
}
