// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../lib/IWETH.sol";
import "../lib/bytes/LibPrefixLengthEncodedByteArray.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC6909/ERC6909.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@permit2/src/interfaces/IAllowanceTransfer.sol";
import "./Dispatcher.sol";
import {LibSwap} from "../lib/LibSwap.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {RestrictTransferFrom} from "./RestrictTransferFrom.sol";
import {TychoVault} from "./TychoVault.sol";

//                                         ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                                   ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                             ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                          ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                       ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷   ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                   ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷       ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                 ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷      ✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷      ✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//              ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷    ✷✷✷✷✷✷✷✷✷✷✷✷✷
//             ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷      ✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷       ✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//            ✷✷✷✷✷✷✷✷✷✷✷✷           ✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷     ✷✷✷✷✷✷✷✷✷         ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//            ✷✷✷✷✷✷✷✷✷✷✷✷                   ✷✷✷✷✷✷           ✷✷✷✷✷✷         ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//            ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷                                   ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//            ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷                  ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//            ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷                  ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//            ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷                                   ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//            ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷         ✷✷✷✷✷✷           ✷✷✷✷✷✷                   ✷✷✷✷✷✷✷✷✷✷✷✷
//            ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷         ✷✷✷✷✷✷✷✷✷     ✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷           ✷✷✷✷✷✷✷✷✷✷✷✷
//             ✷✷✷✷✷✷✷✷✷✷✷✷✷✷       ✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//              ✷✷✷✷✷✷✷✷✷✷✷✷✷    ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷      ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                 ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷      ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                   ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷      ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷    ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                       ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                          ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                             ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                                  ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//                                         ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//
//
//     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷   ✷✷✷✷✷✷       ✷✷✷✷✷✷       ✷✷✷✷✷✷✷         ✷✷✷✷✷✷      ✷✷✷✷✷✷         ✷✷✷✷✷✷✷
//     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷    ✷✷✷✷✷✷    ✷✷✷✷✷✷✷    ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷     ✷✷✷✷✷✷      ✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//           ✷✷✷✷✷✷           ✷✷✷✷✷✷ ✷✷✷✷✷✷     ✷✷✷✷✷✷     ✷✷✷✷✷✷✷   ✷✷✷✷✷✷      ✷✷✷✷✷✷    ✷✷✷✷✷✷     ✷✷✷✷✷✷✷
//           ✷✷✷✷✷✷            ✷✷✷✷✷✷✷✷✷✷      ✷✷✷✷✷✷✷               ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷   ✷✷✷✷✷✷✷      ✷✷✷✷✷✷
//           ✷✷✷✷✷✷              ✷✷✷✷✷✷✷        ✷✷✷✷✷✷      ✷✷✷✷✷✷   ✷✷✷✷✷✷      ✷✷✷✷✷✷    ✷✷✷✷✷✷      ✷✷✷✷✷✷
//           ✷✷✷✷✷✷               ✷✷✷✷✷          ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷    ✷✷✷✷✷✷      ✷✷✷✷✷✷     ✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷✷
//           ✷✷✷✷✷✷               ✷✷✷✷✷              ✷✷✷✷✷✷✷✷        ✷✷✷✷✷✷      ✷✷✷✷✷✷         ✷✷✷✷✷✷✷✷

error TychoRouter__AddressZero();
error TychoRouter__EmptySwaps();
error TychoRouter__NegativeSlippage(uint256 amount, uint256 minAmount);
error TychoRouter__MessageValueMismatch(uint256 value, uint256 amount);
error TychoRouter__InvalidDataLength();
error TychoRouter__UndefinedMinAmountOut();
error TychoRouter__ExcessiveSolverContributionNeeded(
    uint256 required, uint256 max
);

contract TychoRouter is AccessControl, Dispatcher, Pausable, TychoVault {
    IWETH private immutable _weth;
    uint16 private _routerFeeOnOutputBps; // Router fee on output amount in basis points (e.g., 1 = 0.01%)
    uint16 private _routerFeeOnSolverFeeBps; // Router fee on solver fee in basis points (e.g., 1 = 0.01%)
    address private _feeTaker; // Address of the fee executor contract
    address private _routerFeeReceiver; // Address that receives router fees in their vault

    // Per-user custom router fees on output amount
    mapping(address => uint16) private _userRouterFeeOnOutput;
    mapping(address => bool) private _hasCustomRouterFeeOnOutput;

    // Per-user custom router fees on solver fee
    mapping(address => uint16) private _userRouterFeeOnSolverFee;
    mapping(address => bool) private _hasCustomRouterFeeOnSolverFee;

    using SafeERC20 for IERC20;
    using LibPrefixLengthEncodedByteArray for bytes;
    using LibSwap for bytes;

    //keccak256("NAME_OF_ROLE") : save gas on deployment
    bytes32 public constant EXECUTOR_SETTER_ROLE =
        0x6a1dd52dcad5bd732e45b6af4e7344fa284e2d7d4b23b5b09cb55d36b0685c87;
    bytes32 public constant PAUSER_ROLE =
        0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a;
    bytes32 public constant UNPAUSER_ROLE =
        0x427da25fe773164f88948d3e215c94b6554e2ed5e5f203a821c9f2f6131cf75a;
    bytes32 public constant FUND_RESCUER_ROLE =
        0x912e45d663a6f4cc1d0491d8f046e06c616f40352565ea1cdb86a0e1aaefa41b;
    bytes32 public constant ROUTER_FEE_SETTER_ROLE =
        0x8c2f2db0d2b0e5a5c8b5e8f8b5e8f8b5e8f8b5e8f8b5e8f8b5e8f8b5e8f8b5e8;

    event Withdrawal(
        address indexed token, uint256 amount, address indexed receiver
    );
    event RouterFeeOnOutputUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event RouterFeeOnSolverFeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event UserRouterFeeOnOutputUpdated(
        address indexed user, uint16 oldFeeBps, uint16 newFeeBps
    );
    event UserRouterFeeOnSolverFeeUpdated(
        address indexed user, uint16 oldFeeBps, uint16 newFeeBps
    );
    event UserRouterFeeOnOutputRemoved(address indexed user);
    event UserRouterFeeOnSolverFeeRemoved(address indexed user);
    event FeeTakerUpdated(address oldExecutor, address newExecutor);
    event RouterFeeReceiverUpdated(address oldReceiver, address newReceiver);

    constructor(address _permit2, address weth, address routerFeeReceiver)
        Dispatcher(_permit2)
    {
        if (
            _permit2 == address(0) || weth == address(0)
                || routerFeeReceiver == address(0)
        ) {
            revert TychoRouter__AddressZero();
        }
        permit2 = IAllowanceTransfer(_permit2);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _weth = IWETH(weth);
        _routerFeeReceiver = routerFeeReceiver;
    }

    /**
     * @dev Override to resolve multiple inheritance
     * Delegates to parent implementations (TychoVault)
     */
    function _updateDeltaAccounting(
        address user,
        address token,
        int256 deltaChange
    ) internal override(RestrictTransferFrom, TychoVault) {
        super._updateDeltaAccounting(user, token, deltaChange);
    }

    /**
     * @dev Override to resolve multiple inheritance
     * Uses TychoVault's implementation
     */
    function _debitVault(address user, address token, uint256 amount)
        internal
        override(RestrictTransferFrom, TychoVault)
    {
        super._debitVault(user, token, amount);
    }

    /**
     * @dev Override to resolve multiple inheritance
     * Combines AccessControl and ERC6909 (via TychoVault) interface support
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC6909)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Executes a swap operation based on a predefined swap graph, supporting internal token amount splits.
     *         This function enables multi-step swaps, optional ETH wrapping/unwrapping, and validates the output amount
     *         against a user-specified minimum.
     *
     * @dev
     * - If `wrapEth` is true, the contract wraps the provided native ETH into WETH and uses it as the sell token.
     * - If `unwrapEth` is true, the contract converts the resulting WETH back into native ETH before sending it to the receiver.
     * - Swaps are executed sequentially using the `_swap` function.
     * - If the swap output is less than minAmountOut, the solver must subsidize from their own funds.
     * - Reverts if the required solver contribution exceeds maxSolverContribution.
     *
     * @param amountIn The input token amount to be swapped.
     * @param tokenIn The address of the input token. Use `address(0)` for native ETH
     * @param tokenOut The address of the output token. Use `address(0)` for native ETH
     * @param minAmountOut The minimum amount that must be received by the receiver. Solver covers shortfall up to maxSolverContribution.
     * @param maxSolverContribution Maximum amount the solver will pay out of pocket to make the trade succeed.
     * @param wrapEth If true, wraps the input token (native ETH) into WETH.
     * @param unwrapEth If true, unwraps the resulting WETH into native ETH and sends it to the receiver.
     * @param nTokens The total number of tokens involved in the swap graph (used to initialize arrays for internal calculations).
     * @param receiver The address to receive the output tokens.
     * @param isTransferFromAllowed If false, the contract will assume that the input token is already transferred to the contract and don't allow any transferFroms
     * @param swaps Encoded swap graph data containing details of each swap.
     *
     * @return amountOut The total amount of the output token received by the receiver.
     */
    function splitSwap(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        bool wrapEth,
        bool unwrapEth,
        uint256 nTokens,
        address receiver,
        bool isTransferFromAllowed,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swaps
    ) public payable whenNotPaused nonReentrant returns (uint256 amountOut) {
        uint256 initialBalanceTokenOut = _balanceOf(tokenOut, receiver);
        _tstoreTransferFromInfo(tokenIn, amountIn, false, isTransferFromAllowed);

        return _splitSwapChecked(
            amountIn,
            tokenIn,
            tokenOut,
            minAmountOut,
            maxSolverContribution,
            initialBalanceTokenOut,
            wrapEth,
            unwrapEth,
            nTokens,
            receiver,
            solverFeeBps,
            solverFeeReceiver,
            swaps
        );
    }

    /**
     * @notice Executes a swap operation based on a predefined swap graph, supporting internal token amount splits.
     *         This function enables multi-step swaps, optional ETH wrapping/unwrapping, and validates the output amount
     *         against a user-specified minimum.
     *
     * @dev
     * - If `wrapEth` is true, the contract wraps the provided native ETH into WETH and uses it as the sell token.
     * - If `unwrapEth` is true, the contract converts the resulting WETH back into native ETH before sending it to the receiver.
     * - For ERC20 tokens, Permit2 is used to approve and transfer tokens from the caller to the router.
     * - Swaps are executed sequentially using the `_swap` function.
     * - If the swap output is less than minAmountOut, the solver must subsidize from their own funds.
     * - Reverts if the required solver contribution exceeds maxSolverContribution.
     *
     * @param amountIn The input token amount to be swapped.
     * @param tokenIn The address of the input token. Use `address(0)` for native ETH
     * @param tokenOut The address of the output token. Use `address(0)` for native ETH
     * @param minAmountOut The minimum amount that must be received by the receiver. Solver covers shortfall up to maxSolverContribution.
     * @param maxSolverContribution Maximum amount the solver will pay out of pocket to make the trade succeed.
     * @param wrapEth If true, wraps the input token (native ETH) into WETH.
     * @param unwrapEth If true, unwraps the resulting WETH into native ETH and sends it to the receiver.
     * @param nTokens The total number of tokens involved in the swap graph (used to initialize arrays for internal calculations).
     * @param receiver The address to receive the output tokens.
     * @param permitSingle A Permit2 structure containing token approval details for the input token. Ignored if `wrapEth` is true.
     * @param signature A valid signature authorizing the Permit2 approval. Ignored if `wrapEth` is true.
     * @param swaps Encoded swap graph data containing details of each swap.
     *
     * @return amountOut The total amount of the output token received by the receiver.
     */
    function splitSwapPermit2(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        bool wrapEth,
        bool unwrapEth,
        uint256 nTokens,
        address receiver,
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swaps
    ) external payable whenNotPaused nonReentrant returns (uint256 amountOut) {
        uint256 initialBalanceTokenOut = _balanceOf(tokenOut, receiver);
        // For native ETH, assume funds already in our router. Else, handle approval.
        if (tokenIn != address(0)) {
            permit2.permit(msg.sender, permitSingle, signature);
        }
        _tstoreTransferFromInfo(tokenIn, amountIn, true, true);

        return _splitSwapChecked(
            amountIn,
            tokenIn,
            tokenOut,
            minAmountOut,
            maxSolverContribution,
            initialBalanceTokenOut,
            wrapEth,
            unwrapEth,
            nTokens,
            receiver,
            solverFeeBps,
            solverFeeReceiver,
            swaps
        );
    }

    /**
     * @notice Executes a swap operation based on a predefined swap graph with no split routes.
     *         This function enables multi-step swaps, optional ETH wrapping/unwrapping, and validates the output amount
     *         against a user-specified minimum.
     *
     * @dev
     * - If `wrapEth` is true, the contract wraps the provided native ETH into WETH and uses it as the sell token.
     * - If `unwrapEth` is true, the contract converts the resulting WETH back into native ETH before sending it to the receiver.
     * - Swaps are executed sequentially using the `_swap` function.
     * - If the swap output is less than minAmountOut, the solver must subsidize from their own funds.
     * - Reverts if the required solver contribution exceeds maxSolverContribution.
     *
     * @param amountIn The input token amount to be swapped.
     * @param tokenIn The address of the input token. Use `address(0)` for native ETH
     * @param tokenOut The address of the output token. Use `address(0)` for native ETH
     * @param minAmountOut The minimum amount that must be received by the receiver. Solver covers shortfall up to maxSolverContribution.
     * @param maxSolverContribution Maximum amount the solver will pay out of pocket to make the trade succeed.
     * @param wrapEth If true, wraps the input token (native ETH) into WETH.
     * @param unwrapEth If true, unwraps the resulting WETH into native ETH and sends it to the receiver.
     * @param receiver The address to receive the output tokens.
     * @param isTransferFromAllowed If false, the contract will assume that the input token is already transferred to the contract and don't allow any transferFroms
     * @param swaps Encoded swap graph data containing details of each swap.
     *
     * @return amountOut The total amount of the output token received by the receiver.
     */
    function sequentialSwap(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        bool wrapEth,
        bool unwrapEth,
        address receiver,
        bool isTransferFromAllowed,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swaps
    ) public payable whenNotPaused nonReentrant returns (uint256 amountOut) {
        uint256 initialBalanceTokenOut = _balanceOf(tokenOut, receiver);
        _tstoreTransferFromInfo(tokenIn, amountIn, false, isTransferFromAllowed);

        return _sequentialSwapChecked(
            amountIn,
            tokenIn,
            tokenOut,
            minAmountOut,
            maxSolverContribution,
            initialBalanceTokenOut,
            wrapEth,
            unwrapEth,
            receiver,
            solverFeeBps,
            solverFeeReceiver,
            swaps
        );
    }

    /**
     * @notice Executes a swap operation based on a predefined swap graph with no split routes.
     *         This function enables multi-step swaps, optional ETH wrapping/unwrapping, and validates the output amount
     *         against a user-specified minimum.
     *
     * @dev
     * - If `wrapEth` is true, the contract wraps the provided native ETH into WETH and uses it as the sell token.
     * - If `unwrapEth` is true, the contract converts the resulting WETH back into native ETH before sending it to the receiver.
     * - For ERC20 tokens, Permit2 is used to approve and transfer tokens from the caller to the router.
     * - If the swap output is less than minAmountOut, the solver must subsidize from their own funds.
     * - Reverts if the required solver contribution exceeds maxSolverContribution.
     *
     * @param amountIn The input token amount to be swapped.
     * @param tokenIn The address of the input token. Use `address(0)` for native ETH
     * @param tokenOut The address of the output token. Use `address(0)` for native ETH
     * @param minAmountOut The minimum amount that must be received by the receiver. Solver covers shortfall up to maxSolverContribution.
     * @param maxSolverContribution Maximum amount the solver will pay out of pocket to make the trade succeed.
     * @param wrapEth If true, wraps the input token (native ETH) into WETH.
     * @param unwrapEth If true, unwraps the resulting WETH into native ETH and sends it to the receiver.
     * @param receiver The address to receive the output tokens.
     * @param permitSingle A Permit2 structure containing token approval details for the input token. Ignored if `wrapEth` is true.
     * @param signature A valid signature authorizing the Permit2 approval. Ignored if `wrapEth` is true.
     * @param swaps Encoded swap graph data containing details of each swap.
     *
     * @return amountOut The total amount of the output token received by the receiver.
     */
    function sequentialSwapPermit2(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        bool wrapEth,
        bool unwrapEth,
        address receiver,
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swaps
    ) external payable whenNotPaused nonReentrant returns (uint256 amountOut) {
        uint256 initialBalanceTokenOut = _balanceOf(tokenOut, receiver);
        // For native ETH, assume funds already in our router. Else, handle approval.
        if (tokenIn != address(0)) {
            permit2.permit(msg.sender, permitSingle, signature);
        }

        _tstoreTransferFromInfo(tokenIn, amountIn, true, true);

        return _sequentialSwapChecked(
            amountIn,
            tokenIn,
            tokenOut,
            minAmountOut,
            maxSolverContribution,
            initialBalanceTokenOut,
            wrapEth,
            unwrapEth,
            receiver,
            solverFeeBps,
            solverFeeReceiver,
            swaps
        );
    }

    /**
     * @notice Executes a single swap operation.
     *         This function enables optional ETH wrapping/unwrapping, and validates the output amount against a user-specified minimum.
     *
     * @dev
     * - If `wrapEth` is true, the contract wraps the provided native ETH into WETH and uses it as the sell token.
     * - If `unwrapEth` is true, the contract converts the resulting WETH back into native ETH before sending it to the receiver.
     * - If the swap output is less than minAmountOut, the solver must subsidize from their own funds.
     * - Reverts if the required solver contribution exceeds maxSolverContribution.
     *
     * @param amountIn The input token amount to be swapped.
     * @param tokenIn The address of the input token. Use `address(0)` for native ETH
     * @param tokenOut The address of the output token. Use `address(0)` for native ETH
     * @param minAmountOut The minimum amount that must be received by the receiver. Solver covers shortfall up to maxSolverContribution.
     * @param maxSolverContribution Maximum amount the solver will pay out of pocket to make the trade succeed.
     * @param wrapEth If true, wraps the input token (native ETH) into WETH.
     * @param unwrapEth If true, unwraps the resulting WETH into native ETH and sends it to the receiver.
     * @param receiver The address to receive the output tokens.
     * @param isTransferFromAllowed If false, the contract will assume that the input token is already transferred to the contract and don't allow any transferFroms
     * @param swapData Encoded swap details.
     *
     * @return amountOut The total amount of the output token received by the receiver.
     */
    function singleSwap(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        bool wrapEth,
        bool unwrapEth,
        address receiver,
        bool isTransferFromAllowed,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swapData
    ) public payable whenNotPaused nonReentrant returns (uint256 amountOut) {
        uint256 initialBalanceTokenOut = _balanceOf(tokenOut, receiver);
        _tstoreTransferFromInfo(tokenIn, amountIn, false, isTransferFromAllowed);

        return _singleSwap(
            amountIn,
            tokenIn,
            tokenOut,
            minAmountOut,
            maxSolverContribution,
            initialBalanceTokenOut,
            wrapEth,
            unwrapEth,
            receiver,
            solverFeeBps,
            solverFeeReceiver,
            swapData
        );
    }

    /**
     * @notice Executes a single swap operation.
     *         This function enables optional ETH wrapping/unwrapping, and validates the output amount
     *         against a user-specified minimum.
     *
     * @dev
     * - If `wrapEth` is true, the contract wraps the provided native ETH into WETH and uses it as the sell token.
     * - If `unwrapEth` is true, the contract converts the resulting WETH back into native ETH before sending it to the receiver.
     * - For ERC20 tokens, Permit2 is used to approve and transfer tokens from the caller to the router.
     * - If the swap output is less than minAmountOut, the solver must subsidize from their own funds.
     * - Reverts if the required solver contribution exceeds maxSolverContribution.
     *
     * @param amountIn The input token amount to be swapped.
     * @param tokenIn The address of the input token. Use `address(0)` for native ETH
     * @param tokenOut The address of the output token. Use `address(0)` for native ETH
     * @param minAmountOut The minimum amount that must be received by the receiver. Solver covers shortfall up to maxSolverContribution.
     * @param maxSolverContribution Maximum amount the solver will pay out of pocket to make the trade succeed.
     * @param wrapEth If true, wraps the input token (native ETH) into WETH.
     * @param unwrapEth If true, unwraps the resulting WETH into native ETH and sends it to the receiver.
     * @param receiver The address to receive the output tokens.
     * @param permitSingle A Permit2 structure containing token approval details for the input token. Ignored if `wrapEth` is true.
     * @param signature A valid signature authorizing the Permit2 approval. Ignored if `wrapEth` is true.
     * @param swapData Encoded swap details.
     *
     * @return amountOut The total amount of the output token received by the receiver.
     */
    function singleSwapPermit2(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        bool wrapEth,
        bool unwrapEth,
        address receiver,
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swapData
    ) external payable whenNotPaused nonReentrant returns (uint256 amountOut) {
        uint256 initialBalanceTokenOut = _balanceOf(tokenOut, receiver);
        // For native ETH, assume funds already in our router. Else, handle approval.
        if (tokenIn != address(0)) {
            permit2.permit(msg.sender, permitSingle, signature);
        }
        _tstoreTransferFromInfo(tokenIn, amountIn, true, true);

        return _singleSwap(
            amountIn,
            tokenIn,
            tokenOut,
            minAmountOut,
            maxSolverContribution,
            initialBalanceTokenOut,
            wrapEth,
            unwrapEth,
            receiver,
            solverFeeBps,
            solverFeeReceiver,
            swapData
        );
    }

    /**
     * @notice Internal implementation of the core swap logic shared between splitSwap() and splitSwapPermit2().
     *
     * @notice This function centralizes the swap execution logic.
     * @notice For detailed documentation on parameters and behavior, see the documentation for
     * splitSwap() and splitSwapPermit2() functions.
     *
     */
    // Reentrancy protection is handled by nonReentrant modifier on public functions
    // slither-disable-start reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events
    function _splitSwapChecked(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        uint256 initialBalanceTokenOut,
        bool wrapEth,
        bool unwrapEth,
        uint256 nTokens,
        address receiver,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swaps
    ) internal returns (uint256 amountOut) {
        if (receiver == address(0)) {
            revert TychoRouter__AddressZero();
        }
        if (minAmountOut == 0) {
            revert TychoRouter__UndefinedMinAmountOut();
        }

        // Assume funds are already in the router.
        if (wrapEth) {
            _wrapETH(amountIn);
            tokenIn = address(_weth);
            // TODO credit the transient storage accounting
        }

        amountOut = _splitSwap(amountIn, nTokens, swaps);

        // Deduct fees (both solution and router fees)
        bool hasFees;
        (amountOut, hasFees) = _takeFees(
            amountOut,
            tokenOut,
            unwrapEth,
            receiver,
            solverFeeBps,
            solverFeeReceiver
        );

        // Store the actual amount available in router (after fees, before solver contribution)
        uint256 amountInRouter = amountOut;

        // Check if solver needs to subsidize the trade
        if (amountOut < minAmountOut) {
            uint256 requiredContribution = minAmountOut - amountOut;
            if (requiredContribution > maxSolverContribution) {
                revert TychoRouter__ExcessiveSolverContributionNeeded(
                    requiredContribution, maxSolverContribution
                );
            }
            // Debit the solver's vault balance and transfer contribution to receiver
            address contributionToken = unwrapEth ? address(_weth) : tokenOut;
            _debitVault(msg.sender, contributionToken, requiredContribution);

            if (unwrapEth) {
                // If unwrapping, withdraw WETH and send as ETH
                _weth.withdraw(requiredContribution);
                Address.sendValue(payable(receiver), requiredContribution);
            } else {
                // Transfer ERC20 directly to receiver
                IERC20(contributionToken)
                    .safeTransfer(receiver, requiredContribution);
            }

            // Update amountOut to reflect total received by receiver
            amountOut = minAmountOut;
        }

        address settlementToken = unwrapEth ? address(_weth) : tokenOut;

        // Finalize all transient deltas to persistent storage
        _finalizeBalances(msg.sender, tokenIn, amountIn);

        // Transfer the amount from router to receiver
        if (unwrapEth) {
            _unwrapETH(amountInRouter);
            Address.sendValue(payable(receiver), amountInRouter);
        } else {
            IERC20(tokenOut).safeTransfer(receiver, amountInRouter);
        }

        _verifyAmountOutWasReceived(
            tokenIn,
            tokenOut,
            initialBalanceTokenOut,
            amountOut,
            receiver,
            amountIn
        );
    }
    // slither-disable-end reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events

    /**
     * @notice Internal implementation of the core swap logic shared between singleSwap() and singleSwapPermit2().
     *
     * @notice This function centralizes the swap execution logic.
     * @notice For detailed documentation on parameters and behavior, see the documentation for
     * singleSwap() and singleSwapPermit2() functions.
     *
     */
    // Reentrancy protection is handled by nonReentrant modifier on public functions
    // slither-disable-start reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events
    function _singleSwap(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        uint256 initialBalanceTokenOut,
        bool wrapEth,
        bool unwrapEth,
        address receiver,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swap_
    ) internal returns (uint256 amountOut) {
        if (receiver == address(0)) {
            revert TychoRouter__AddressZero();
        }
        if (minAmountOut == 0) {
            revert TychoRouter__UndefinedMinAmountOut();
        }

        // Assume funds are already in the router.
        if (wrapEth) {
            _wrapETH(amountIn);
            tokenIn = address(_weth);
            // TODO credit the transient storage accounting
        }

        (address executor, bytes calldata protocolData) =
            swap_.decodeSingleSwap();

        (amountOut,,) = _callSwapOnExecutor(executor, amountIn, protocolData);

        // Deduct fees (both solution and router fees)
        bool hasFees;
        (amountOut, hasFees) = _takeFees(
            amountOut,
            tokenOut,
            unwrapEth,
            receiver,
            solverFeeBps,
            solverFeeReceiver
        );

        // Store the actual amount available in router (after fees, before solver contribution)
        uint256 amountInRouter = amountOut;

        // Check if solver needs to subsidize the trade
        if (amountOut < minAmountOut) {
            uint256 requiredContribution = minAmountOut - amountOut;
            if (requiredContribution > maxSolverContribution) {
                revert TychoRouter__ExcessiveSolverContributionNeeded(
                    requiredContribution, maxSolverContribution
                );
            }
            // Debit the solver's vault balance and transfer contribution to receiver
            address contributionToken = unwrapEth ? address(_weth) : tokenOut;
            _debitVault(msg.sender, contributionToken, requiredContribution);

            if (unwrapEth) {
                // If unwrapping, withdraw WETH and send as ETH
                _weth.withdraw(requiredContribution);
                Address.sendValue(payable(receiver), requiredContribution);
            } else {
                // Transfer ERC20 directly to receiver
                IERC20(contributionToken)
                    .safeTransfer(receiver, requiredContribution);
            }

            // Update amountOut to reflect total received by receiver
            amountOut = minAmountOut;
        }

        address settlementToken = unwrapEth ? address(_weth) : tokenOut;

        // Finalize all transient deltas to persistent storage
        _finalizeBalances(msg.sender, tokenIn, amountIn);

        // Transfer the amount from router to receiver
        if (unwrapEth) {
            _unwrapETH(amountInRouter);
            Address.sendValue(payable(receiver), amountInRouter);
        } else {
            IERC20(tokenOut).safeTransfer(receiver, amountInRouter);
        }

        _verifyAmountOutWasReceived(
            tokenIn,
            tokenOut,
            initialBalanceTokenOut,
            amountOut,
            receiver,
            amountIn
        );
    }
    // slither-disable-end reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events

    /**
     * @notice Internal implementation of the core swap logic shared between sequentialSwap() and sequentialSwapPermit2().
     *
     * @notice This function centralizes the swap execution logic.
     * @notice For detailed documentation on parameters and behavior, see the documentation for
     * sequentialSwap() and sequentialSwapPermit2() functions.
     *
     */
    // Reentrancy protection is handled by nonReentrant modifier on public functions
    // slither-disable-start reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events
    function _sequentialSwapChecked(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxSolverContribution,
        uint256 initialBalanceTokenOut,
        bool wrapEth,
        bool unwrapEth,
        address receiver,
        uint16 solverFeeBps,
        address solverFeeReceiver,
        bytes calldata swaps
    ) internal returns (uint256 amountOut) {
        if (receiver == address(0)) {
            revert TychoRouter__AddressZero();
        }
        if (minAmountOut == 0) {
            revert TychoRouter__UndefinedMinAmountOut();
        }

        // Assume funds are already in the router.
        if (wrapEth) {
            _wrapETH(amountIn);
            tokenIn = address(_weth);
            // TODO credit the transient storage accounting
        }

        amountOut = _sequentialSwap(amountIn, swaps);

        // Deduct fees (both solution and router fees)
        bool hasFees;
        (amountOut, hasFees) = _takeFees(
            amountOut,
            tokenOut,
            unwrapEth,
            receiver,
            solverFeeBps,
            solverFeeReceiver
        );

        // Store the actual amount available in router (after fees, before solver contribution)
        uint256 amountInRouter = amountOut;

        // Check if solver needs to subsidize the trade
        if (amountOut < minAmountOut) {
            uint256 requiredContribution = minAmountOut - amountOut;
            if (requiredContribution > maxSolverContribution) {
                revert TychoRouter__ExcessiveSolverContributionNeeded(
                    requiredContribution, maxSolverContribution
                );
            }
            // Debit the solver's vault balance and transfer contribution to receiver
            address contributionToken = unwrapEth ? address(_weth) : tokenOut;
            _debitVault(msg.sender, contributionToken, requiredContribution);

            if (unwrapEth) {
                // If unwrapping, withdraw WETH and send as ETH
                _weth.withdraw(requiredContribution);
                Address.sendValue(payable(receiver), requiredContribution);
            } else {
                // Transfer ERC20 directly to receiver
                IERC20(contributionToken)
                    .safeTransfer(receiver, requiredContribution);
            }

            // Update amountOut to reflect total received by receiver
            amountOut = minAmountOut;
        }

        address settlementToken = unwrapEth ? address(_weth) : tokenOut;

        // Finalize all transient deltas to persistent storage
        _finalizeBalances(msg.sender, tokenIn, amountIn);

        // Transfer the amount from router to receiver
        if (unwrapEth) {
            _unwrapETH(amountInRouter);
            Address.sendValue(payable(receiver), amountInRouter);
        } else {
            IERC20(tokenOut).safeTransfer(receiver, amountInRouter);
        }

        _verifyAmountOutWasReceived(
            tokenIn,
            tokenOut,
            initialBalanceTokenOut,
            amountOut,
            receiver,
            amountIn
        );
    }
    // slither-disable-end reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events

    /**
     * @dev Executes sequential swaps as defined by the provided swap graph.
     *
     * This function processes a series of swaps encoded in the `swaps_` byte array. Each swap operation determines:
     * - The indices of the input and output tokens (via `tokenInIndex()` and `tokenOutIndex()`).
     * - The portion of the available amount to be used for the swap, indicated by the `split` value.
     *
     * Three important notes:
     * - The contract assumes that token indexes follow a specific order: the sell token is at index 0, followed by any
     *  intermediary tokens, and finally the buy token.
     * - A `split` value of 0 is interpreted as 100% of the available amount (i.e., the entire remaining balance).
     *  This means that in scenarios without explicit splits the value should be 0, and when splits are present,
     *  the last swap should also have a split value of 0.
     * - In case of cyclic swaps, the output token is the same as the input token.
     *  `cyclicSwapAmountOut` is used to track the amount of the output token, and is updated when
     *  the `tokenOutIndex` is 0.
     *
     * @param amountIn The initial amount of the sell token to be swapped.
     * @param nTokens The total number of tokens involved in the swap path, used to initialize arrays for internal tracking.
     * @param swaps_ Encoded swap graph data containing the details of each swap operation.
     *
     * @return The total amount of the buy token obtained after all swaps have been executed.
     */
    function _splitSwap(
        uint256 amountIn,
        uint256 nTokens,
        bytes calldata swaps_
    ) internal returns (uint256) {
        if (swaps_.length == 0) {
            revert TychoRouter__EmptySwaps();
        }

        uint256 currentAmountIn;
        uint256 currentAmountOut;
        uint8 tokenInIndex = 0;
        uint8 tokenOutIndex = 0;
        uint24 split;
        address executor;
        bytes calldata protocolData;
        bytes calldata swapData;

        uint256[] memory remainingAmounts = new uint256[](nTokens);
        uint256[] memory amounts = new uint256[](nTokens);
        uint256 cyclicSwapAmountOut = 0;
        amounts[0] = amountIn;
        remainingAmounts[0] = amountIn;

        while (swaps_.length > 0) {
            (swapData, swaps_) = swaps_.next();

            (tokenInIndex, tokenOutIndex, split, executor, protocolData) =
                swapData.decodeSplitSwap();

            currentAmountIn = split > 0
                ? (amounts[tokenInIndex] * split) / 0xffffff
                : remainingAmounts[tokenInIndex];

            (currentAmountOut,,) =
                _callSwapOnExecutor(executor, currentAmountIn, protocolData);
            // Checks if the output token is the same as the input token
            if (tokenOutIndex == 0) {
                cyclicSwapAmountOut += currentAmountOut;
            } else {
                amounts[tokenOutIndex] += currentAmountOut;
            }
            remainingAmounts[tokenOutIndex] += currentAmountOut;
            remainingAmounts[tokenInIndex] -= currentAmountIn;
        }
        return tokenOutIndex == 0 ? cyclicSwapAmountOut : amounts[tokenOutIndex];
    }

    /**
     * @dev Executes sequential swaps as defined by the provided swap graph.
     *
     * @param amountIn The initial amount of the sell token to be swapped.
     * @param swaps_ Encoded swap graph data containing the details of each swap operation.
     *
     * @return calculatedAmount The total amount of the buy token obtained after all swaps have been executed.
     */
    function _sequentialSwap(uint256 amountIn, bytes calldata swaps_)
        internal
        returns (uint256 calculatedAmount)
    {
        bytes calldata swap;
        calculatedAmount = amountIn;
        while (swaps_.length > 0) {
            (swap, swaps_) = swaps_.next();

            (address executor, bytes calldata protocolData) =
                swap.decodeSingleSwap();

            (calculatedAmount,,) =
                _callSwapOnExecutor(executor, calculatedAmount, protocolData);
        }
    }

    /**
     * @dev We use the fallback function to allow flexibility on callback.
     */
    fallback(bytes calldata data) external returns (bytes memory) {
        return _callHandleCallbackOnExecutor(data);
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
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
     * @dev Entrypoint to add or replace an approved executor contract address
     * @param targets address of the executor contract
     */
    function setExecutors(address[] memory targets)
        external
        onlyRole(EXECUTOR_SETTER_ROLE)
    {
        for (uint256 i = 0; i < targets.length; i++) {
            _setExecutor(targets[i]);
        }
    }

    /**
     * @dev Entrypoint to remove an approved executor contract address
     * @param target address of the executor contract
     */
    function removeExecutor(address target)
        external
        onlyRole(EXECUTOR_SETTER_ROLE)
    {
        _removeExecutor(target);
    }

    /**
     * @dev Sets the router platform fee on output amount in basis points
     * @param feeBps The fee in basis points (e.g., 1 = 0.01%, 100 = 1%)
     */
    function setRouterFeeOnOutput(uint16 feeBps)
        external
        onlyRole(ROUTER_FEE_SETTER_ROLE)
    {
        uint16 oldFeeBps = _routerFeeOnOutputBps;
        _routerFeeOnOutputBps = feeBps;
        emit RouterFeeOnOutputUpdated(oldFeeBps, feeBps);
    }

    /**
     * @dev Returns the current router platform fee on output amount in basis points
     * @return The fee in basis points
     */
    function getRouterFeeOnOutput() external view returns (uint16) {
        return _routerFeeOnOutputBps;
    }

    /**
     * @dev Sets a custom router fee on output amount for a specific user
     * @param user The user address to set the custom fee for
     * @param feeBps The fee in basis points (e.g., 1 = 0.01%, 100 = 1%)
     */
    function setRouterFeeOnOutputForUser(address user, uint16 feeBps)
        external
        onlyRole(ROUTER_FEE_SETTER_ROLE)
    {
        uint16 oldFeeBps = _hasCustomRouterFeeOnOutput[user]
            ? _userRouterFeeOnOutput[user]
            : _routerFeeOnOutputBps;
        _userRouterFeeOnOutput[user] = feeBps;
        _hasCustomRouterFeeOnOutput[user] = true;
        emit UserRouterFeeOnOutputUpdated(user, oldFeeBps, feeBps);
    }

    /**
     * @dev Removes the custom router fee on output amount for a specific user, reverting to default
     * @param user The user address to remove the custom fee from
     */
    function removeRouterFeeOnOutputForUser(address user)
        external
        onlyRole(ROUTER_FEE_SETTER_ROLE)
    {
        _hasCustomRouterFeeOnOutput[user] = false;
        delete _userRouterFeeOnOutput[user];
        emit UserRouterFeeOnOutputRemoved(user);
    }

    /**
     * @dev Returns the effective router fee on output amount for a specific user
     * @param user The user address to check
     * @return The fee in basis points (custom if set, otherwise default)
     */
    function getRouterFeeOnOutputForUser(address user)
        external
        view
        returns (uint16)
    {
        return _hasCustomRouterFeeOnOutput[user]
            ? _userRouterFeeOnOutput[user]
            : _routerFeeOnOutputBps;
    }

    /**
     * @dev Sets the router platform fee on solver fee in basis points
     * @param feeBps The fee in basis points (e.g., 1 = 0.01%, 100 = 1%)
     */
    function setRouterFeeOnSolverFee(uint16 feeBps)
        external
        onlyRole(ROUTER_FEE_SETTER_ROLE)
    {
        uint16 oldFeeBps = _routerFeeOnSolverFeeBps;
        _routerFeeOnSolverFeeBps = feeBps;
        emit RouterFeeOnSolverFeeUpdated(oldFeeBps, feeBps);
    }

    /**
     * @dev Returns the current router platform fee on solver fee in basis points
     * @return The fee in basis points
     */
    function getRouterFeeOnSolverFee() external view returns (uint16) {
        return _routerFeeOnSolverFeeBps;
    }

    /**
     * @dev Sets a custom router fee on solver fee for a specific user
     * @param user The user address to set the custom fee for
     * @param feeBps The fee in basis points (e.g., 1 = 0.01%, 100 = 1%)
     */
    function setRouterFeeOnSolverFeeForUser(address user, uint16 feeBps)
        external
        onlyRole(ROUTER_FEE_SETTER_ROLE)
    {
        uint16 oldFeeBps = _hasCustomRouterFeeOnSolverFee[user]
            ? _userRouterFeeOnSolverFee[user]
            : _routerFeeOnSolverFeeBps;
        _userRouterFeeOnSolverFee[user] = feeBps;
        _hasCustomRouterFeeOnSolverFee[user] = true;
        emit UserRouterFeeOnSolverFeeUpdated(user, oldFeeBps, feeBps);
    }

    /**
     * @dev Removes the custom router fee on solver fee for a specific user, reverting to default
     * @param user The user address to remove the custom fee from
     */
    function removeRouterFeeOnSolverFeeForUser(address user)
        external
        onlyRole(ROUTER_FEE_SETTER_ROLE)
    {
        _hasCustomRouterFeeOnSolverFee[user] = false;
        delete _userRouterFeeOnSolverFee[user];
        emit UserRouterFeeOnSolverFeeRemoved(user);
    }

    /**
     * @dev Returns the effective router fee on solver fee for a specific user
     * @param user The user address to check
     * @return The fee in basis points (custom if set, otherwise default)
     */
    function getRouterFeeOnSolverFeeForUser(address user)
        external
        view
        returns (uint16)
    {
        return _hasCustomRouterFeeOnSolverFee[user]
            ? _userRouterFeeOnSolverFee[user]
            : _routerFeeOnSolverFeeBps;
    }

    /**
     * @notice Sets the fee executor contract address
     * @param feeTaker The address of the fee executor contract
     */
    function setFeeTaker(address feeTaker)
        external
        onlyRole(EXECUTOR_SETTER_ROLE)
    {
        if (feeTaker == address(0)) {
            revert TychoRouter__AddressZero();
        }
        address oldExecutor = _feeTaker;
        _feeTaker = feeTaker;
        emit FeeTakerUpdated(oldExecutor, feeTaker);
    }

    /**
     * @dev Returns the current fee executor address
     */
    function getFeeTaker() external view returns (address) {
        return _feeTaker;
    }

    /**
     * @dev Sets the address that receives router fees
     * @param routerFeeReceiver The address to receive router fees in their vault
     */
    function setRouterFeeReceiver(address routerFeeReceiver)
        external
        onlyRole(ROUTER_FEE_SETTER_ROLE)
    {
        if (routerFeeReceiver == address(0)) {
            revert TychoRouter__AddressZero();
        }
        address oldReceiver = _routerFeeReceiver;
        _routerFeeReceiver = routerFeeReceiver;
        emit RouterFeeReceiverUpdated(oldReceiver, routerFeeReceiver);
    }

    /**
     * @dev Returns the current router fee receiver address
     */
    function getRouterFeeReceiver() external view returns (address) {
        return _routerFeeReceiver;
    }

    /**
     * @dev Allows withdrawing any ERC20 funds if funds get stuck in case of a bug.
     */
    function withdraw(IERC20[] memory tokens, address receiver)
        external
        onlyRole(FUND_RESCUER_ROLE)
    {
        if (receiver == address(0)) revert TychoRouter__AddressZero();

        for (uint256 i = 0; i < tokens.length; i++) {
            // slither-disable-next-line calls-loop
            uint256 tokenBalance = tokens[i].balanceOf(address(this));
            if (tokenBalance > 0) {
                emit Withdrawal(address(tokens[i]), tokenBalance, receiver);
                tokens[i].safeTransfer(receiver, tokenBalance);
            }
        }
    }

    /**
     * @dev Allows withdrawing any NATIVE funds if funds get stuck in case of a bug.
     * The contract should never hold any NATIVE tokens for security reasons.
     */
    function withdrawNative(address receiver)
        external
        onlyRole(FUND_RESCUER_ROLE)
    {
        if (receiver == address(0)) revert TychoRouter__AddressZero();

        uint256 amount = address(this).balance;
        if (amount > 0) {
            emit Withdrawal(address(0), amount, receiver);
            Address.sendValue(payable(receiver), amount);
        }
    }

    /**
     * @dev Wraps a defined amount of ETH.
     * @param amount of native ETH to wrap.
     */
    function _wrapETH(uint256 amount) internal {
        if (msg.value != amount) {
            revert TychoRouter__MessageValueMismatch(msg.value, amount);
        }
        _weth.deposit{value: amount}();
    }

    /**
     * @dev Unwraps a defined amount of WETH.
     * @param amount of WETH to unwrap.
     */
    function _unwrapETH(uint256 amount) internal {
        _weth.withdraw(amount);
    }

    /**
     * @dev Allows this contract to receive native token with empty msg.data from contracts
     */
    receive() external payable {
        require(msg.sender.code.length != 0);
    }

    /**
     * @dev Deducts both solution and router fees using the fee executor
     * @dev Calls FeeTaker with encoded fee data via delegatecall
     * @dev Note: FeeTaker only calculates and credits fees, does NOT transfer to receiver
     * @param amountOut The amount before fee deduction
     * @param tokenOut The output token address
     * @param unwrapEth Whether ETH will be unwrapped (fee is in WETH if true)
     * @param receiver The address to receive the output tokens
     * @param solverFeeBps Solution fee in basis points
     * @param solverFeeReceiver Address to receive the solution fee
     * @return amountAfterFees The amount after fee deductions
     * @return hasFees Whether any fees were taken
     */
    function _takeFees(
        uint256 amountOut,
        address tokenOut,
        bool unwrapEth,
        address receiver,
        uint16 solverFeeBps,
        address solverFeeReceiver
    ) private returns (uint256 amountAfterFees, bool hasFees) {
        // Get the effective router fees for this user (custom or default)
        uint16 effectiveRouterFeeOnOutputBps = _hasCustomRouterFeeOnOutput[
            msg.sender
        ]
            ? _userRouterFeeOnOutput[msg.sender]
            : _routerFeeOnOutputBps;

        uint16 effectiveRouterFeeOnSolverFeeBps = _hasCustomRouterFeeOnSolverFee[
            msg.sender
        ]
            ? _userRouterFeeOnSolverFee[msg.sender]
            : _routerFeeOnSolverFeeBps;

        hasFees = solverFeeBps > 0 || effectiveRouterFeeOnOutputBps > 0
            || effectiveRouterFeeOnSolverFeeBps > 0;

        // TODO double check that it's okay to skip this call
        // with our current encoding - since we are relying on this
        // to send the output amount to the receiver. Find a way around this
        // (like check the reciever of the final swap somehow, and if it's not the
        // receiver we need to send it ourselves here?.
        if (_feeTaker != address(0) && hasFees) {
            address feeToken = unwrapEth ? address(_weth) : tokenOut;

            // Encode fee data: solverFeeBps | solverFeeReceiver |
            // routerFeeOnOutputBps |
            // routerFeeOnSolverFeeBps | routerFeeReceiver | token
            bytes memory feeData = abi.encodePacked(
                solverFeeBps, // solverFeeBps
                solverFeeReceiver, // solverFeeReceiver
                effectiveRouterFeeOnOutputBps, // routerFeeOnOutputBps (custom or default)
                effectiveRouterFeeOnSolverFeeBps, // routerFeeOnSolverFeeBps (custom or default)
                _routerFeeReceiver, // routerFeeReceiver (configurable)
                feeToken // token
            );

            amountOut = _callTakeFees(_feeTaker, amountOut, feeData);
            return (amountOut, true);
        }
        return (amountOut, false);
    }

    /**
     * @dev Verifies that the expected amount of output tokens was received by the receiver.
     * @param tokenIn The input token
     * @param tokenOut The output token
     * @param initialBalanceReceiver The receiver's initial balance
     * @param amountOut The amount received
     * @param receiver The intended receiver
     * @param amountIn The input amount
     */
    function _verifyAmountOutWasReceived(
        address tokenIn,
        address tokenOut,
        uint256 initialBalanceReceiver,
        uint256 amountOut,
        address receiver,
        uint256 amountIn
    ) internal view {
        uint256 currentBalance = _balanceOf(tokenOut, receiver);
        uint256 initialBalance = initialBalanceReceiver;

        if (tokenIn == tokenOut) {
            // If it is an arbitrage, we need to remove the amountIn from the initial balance
            initialBalance -= amountIn;
        }

        uint256 userAmount = currentBalance - initialBalance;
        if (userAmount != amountOut) {
            revert TychoRouter__NegativeSlippage(userAmount, amountOut);
        }
    }
}
