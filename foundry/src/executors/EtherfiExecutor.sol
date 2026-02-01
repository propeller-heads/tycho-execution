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

    address public immutable ethAddress;
    address public immutable eethAddress;
    address public immutable liquidityPoolAddress;
    address public immutable weethAddress;
    address public immutable redemptionManagerAddress;

    constructor(
        address _permit2,
        address _ethAddress,
        address _eethAddress,
        address _liquidityPoolAddress,
        address _weethAddress,
        address _redemptionManagerAddress
    ) RestrictTransferFrom(_permit2) {
        require(
            _ethAddress != address(0), "EtherfiExecutor: ethAddress is zero"
        );
        require(
            _eethAddress != address(0), "EtherfiExecutor: eethAddress is zero"
        );
        require(
            _liquidityPoolAddress != address(0),
            "EtherfiExecutor: liquidityPoolAddress is zero"
        );
        require(
            _weethAddress != address(0), "EtherfiExecutor: weethAddress is zero"
        );
        require(
            _redemptionManagerAddress != address(0),
            "EtherfiExecutor: redemptionManagerAddress is zero"
        );

        ethAddress = _ethAddress;
        eethAddress = _eethAddress;
        liquidityPoolAddress = _liquidityPoolAddress;
        weethAddress = _weethAddress;
        redemptionManagerAddress = _redemptionManagerAddress;
    }

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
            _transfer(address(this), transferType, eethAddress, givenAmount);
            if (approvalNeeded) {
                IERC20(eethAddress)
                    .forceApprove(redemptionManagerAddress, type(uint256).max);
            }

            uint256 balanceBefore = receiver.balance;
            // eETH is share-based and rounds down on amount conversions;
            // cap redeem amount to current balance to avoid 1-wei dust reverts.
            uint256 redeemAmount = IERC20(eethAddress).balanceOf(address(this));
            if (redeemAmount > givenAmount) {
                redeemAmount = givenAmount;
            }
            IEtherfiRedemptionManager(redemptionManagerAddress)
                .redeemEEth(redeemAmount, receiver, ethAddress);
            calculatedAmount = receiver.balance - balanceBefore;
        } else if (direction == EtherfiDirection.EthToEeth) {
            uint256 balanceBefore = IERC20(eethAddress).balanceOf(address(this));
            // deposit() returns shares, not the eETH amount; use balance delta for amount-out.
            // slither-disable-next-line arbitrary-send-eth
            uint256 shares = IEtherfiLiquidityPool(liquidityPoolAddress)
            .deposit{value: givenAmount}();
            uint256 balanceAfter = IERC20(eethAddress).balanceOf(address(this));
            calculatedAmount = balanceAfter - balanceBefore;

            if (receiver != address(this)) {
                uint256 receiverBalanceBefore =
                    IERC20(eethAddress).balanceOf(receiver);
                IERC20(eethAddress).safeTransfer(receiver, calculatedAmount);
                uint256 receiverBalanceAfter =
                    IERC20(eethAddress).balanceOf(receiver);
                calculatedAmount = receiverBalanceAfter - receiverBalanceBefore;
            }
        } else if (direction == EtherfiDirection.EethToWeeth) {
            _transfer(address(this), transferType, eethAddress, givenAmount);
            if (approvalNeeded) {
                IERC20(eethAddress)
                    .forceApprove(weethAddress, type(uint256).max);
            }
            calculatedAmount = IWeETH(weethAddress).wrap(givenAmount);

            if (receiver != address(this)) {
                IERC20(weethAddress).safeTransfer(receiver, calculatedAmount);
            }
        } else if (direction == EtherfiDirection.WeethToEeth) {
            _transfer(address(this), transferType, weethAddress, givenAmount);
            calculatedAmount = IWeETH(weethAddress).unwrap(givenAmount);

            if (receiver != address(this)) {
                IERC20(eethAddress).safeTransfer(receiver, calculatedAmount);
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
