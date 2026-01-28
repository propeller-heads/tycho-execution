// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@interfaces/IExecutor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RestrictTransferFrom} from "../RestrictTransferFrom.sol";

error EtherfiExecutor__InvalidDataLength();
error EtherfiExecutor__InvalidDirection();

interface IEtherfiRedemptionManager {
    function redeemEEth(
        uint256 eEthAmount,
        address receiver,
        address outputToken
    ) external;
}

interface IEtherfiLiquidityPool {
    function deposit() external payable returns (uint256);
}

interface IWeETH {
    function wrap(uint256 _eETHAmount) external returns (uint256);

    function unwrap(uint256 _weETHAmount) external returns (uint256);
}

enum EtherfiDirection {
    EethToEth,
    EthToEeth,
    EethToWeeth,
    WeethToEeth
}

contract EtherfiExecutor is IExecutor, RestrictTransferFrom {
    using SafeERC20 for IERC20;

    constructor(address _permit2) RestrictTransferFrom(_permit2) {}

    address public constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant EETH_ADDRESS =
        0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address public constant LIQUIDITY_POOL_ADDRESS =
        0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address public constant WEETH_ADDRESS =
        0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant REDEMPTION_MANAGER_ADDRESS =
        0xDadEf1fFBFeaAB4f68A9fD181395F68b4e4E7Ae0;

    receive() external payable {}

    // slither-disable-next-line locked-ether
    function swap(uint256 givenAmount, bytes calldata data)
        external
        payable
        returns (uint256 calculatedAmount)
    {
        address receiver;
        TransferType transferType;
        EtherfiDirection direction;
        bool approvalNeeded;

        (receiver, transferType, direction, approvalNeeded) = _decodeData(data);

        if (direction == EtherfiDirection.EethToEth) {
            _transfer(address(this), transferType, EETH_ADDRESS, givenAmount);
            if (approvalNeeded) {
                IERC20(EETH_ADDRESS)
                    .forceApprove(REDEMPTION_MANAGER_ADDRESS, type(uint256).max);
            }

            uint256 balanceBefore = receiver.balance;
            // eETH is share-based and rounds down on amount conversions;
            // cap redeem amount to current balance to avoid 1-wei dust reverts.
            uint256 redeemAmount = IERC20(EETH_ADDRESS).balanceOf(address(this));
            if (redeemAmount > givenAmount) {
                redeemAmount = givenAmount;
            }
            IEtherfiRedemptionManager(REDEMPTION_MANAGER_ADDRESS)
                .redeemEEth(redeemAmount, receiver, ETH_ADDRESS);
            calculatedAmount = receiver.balance - balanceBefore;
        } else if (direction == EtherfiDirection.EthToEeth) {
            uint256 balanceBefore =
                IERC20(EETH_ADDRESS).balanceOf(address(this));
            // deposit() returns shares, not the eETH amount; use balance delta for amount-out.
            // slither-disable-next-line unused-return
            IEtherfiLiquidityPool(LIQUIDITY_POOL_ADDRESS)
            .deposit{value: givenAmount}();
            uint256 balanceAfter = IERC20(EETH_ADDRESS).balanceOf(address(this));
            calculatedAmount = balanceAfter - balanceBefore;

            if (receiver != address(this)) {
                IERC20(EETH_ADDRESS).safeTransfer(receiver, calculatedAmount);
            }
        } else if (direction == EtherfiDirection.EethToWeeth) {
            _transfer(address(this), transferType, EETH_ADDRESS, givenAmount);
            if (approvalNeeded) {
                IERC20(EETH_ADDRESS)
                    .forceApprove(WEETH_ADDRESS, type(uint256).max);
            }
            calculatedAmount = IWeETH(WEETH_ADDRESS).wrap(givenAmount);

            if (receiver != address(this)) {
                IERC20(WEETH_ADDRESS).safeTransfer(receiver, calculatedAmount);
            }
        } else if (direction == EtherfiDirection.WeethToEeth) {
            _transfer(address(this), transferType, WEETH_ADDRESS, givenAmount);
            calculatedAmount = IWeETH(WEETH_ADDRESS).unwrap(givenAmount);

            if (receiver != address(this)) {
                IERC20(EETH_ADDRESS).safeTransfer(receiver, calculatedAmount);
            }
        } else {
            revert EtherfiExecutor__InvalidDirection();
        }
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (
            address receiver,
            TransferType transferType,
            EtherfiDirection direction,
            bool approvalNeeded
        )
    {
        if (data.length != 23) {
            revert EtherfiExecutor__InvalidDataLength();
        }
        receiver = address(bytes20(data[0:20]));
        transferType = TransferType(uint8(data[20]));
        direction = EtherfiDirection(uint8(data[21]));
        approvalNeeded = data[22] != 0;
    }
}
