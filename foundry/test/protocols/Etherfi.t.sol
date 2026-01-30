// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../TychoRouterTestSetup.sol";
import "../TestUtils.sol";
import "@src/executors/EtherfiExecutor.sol";
import {Constants} from "../Constants.sol";

contract EtherfiExecutorExposed is EtherfiExecutor {
    constructor(
        address _permit2,
        address _ethAddress,
        address _eethAddress,
        address _liquidityPoolAddress,
        address _weethAddress,
        address _redemptionManagerAddress
    )
        EtherfiExecutor(
            _permit2,
            _ethAddress,
            _eethAddress,
            _liquidityPoolAddress,
            _weethAddress,
            _redemptionManagerAddress
        )
    {}

    function decodeParams(bytes calldata data)
        external
        pure
        returns (
            address receiver,
            TransferType transferType,
            EtherfiDirection direction,
            bool approvalNeeded
        )
    {
        return _decodeData(data);
    }
}

contract EtherfiExecutorTest is Constants, TestUtils {
    EtherfiExecutorExposed etherfiExposed;

    function setUp() public {
        uint256 forkBlock = 23934489;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);
        etherfiExposed = new EtherfiExecutorExposed(
            PERMIT2_ADDRESS,
            ETH_ADDR_FOR_CURVE,
            EETH_ADDR,
            LIQUIDITY_POOL_ADDR,
            WEETH_ADDR,
            REDEMPTION_MANAGER_ADDR
        );
    }

    function _mintEethToExecutor(uint256 amountIn)
        internal
        returns (uint256 minted)
    {
        bytes memory protocolData = abi.encodePacked(
            address(etherfiExposed),
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EthToEeth,
            false
        );

        vm.deal(address(this), amountIn);
        minted = etherfiExposed.swap{value: amountIn}(amountIn, protocolData);
    }

    function testDecodeParams() public view {
        bytes memory params = abi.encodePacked(
            BOB,
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EethToWeeth,
            true
        );

        (
            address receiver,
            RestrictTransferFrom.TransferType transferType,
            EtherfiDirection direction,
            bool approvalNeeded
        ) = etherfiExposed.decodeParams(params);

        assertEq(receiver, BOB);
        assertEq(
            uint8(transferType), uint8(RestrictTransferFrom.TransferType.None)
        );
        assertEq(uint8(direction), uint8(EtherfiDirection.EethToWeeth));
        assertEq(approvalNeeded, true);
    }

    function testDecodeParamsInvalidDataLength() public {
        bytes memory invalidParams =
            abi.encodePacked(BOB, RestrictTransferFrom.TransferType.None);

        vm.expectRevert(EtherfiExecutor__InvalidDataLength.selector);
        etherfiExposed.decodeParams(invalidParams);
    }

    function testSwapEthToEeth() public {
        uint256 amountIn = 1 ether;
        bytes memory protocolData = abi.encodePacked(
            BOB,
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EthToEeth,
            false
        );

        vm.deal(address(this), amountIn);
        uint256 balanceBefore = IERC20(EETH_ADDR).balanceOf(BOB);

        uint256 amountOut =
            etherfiExposed.swap{value: amountIn}(amountIn, protocolData);

        uint256 balanceAfter = IERC20(EETH_ADDR).balanceOf(BOB);
        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, amountOut);
    }

    function testSwapEethToWeeth() public {
        uint256 minted = _mintEethToExecutor(1 ether);
        bytes memory protocolData = abi.encodePacked(
            BOB,
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EethToWeeth,
            true
        );

        uint256 balanceBefore = IERC20(WEETH_ADDR).balanceOf(BOB);
        uint256 amountOut = etherfiExposed.swap(minted, protocolData);
        uint256 balanceAfter = IERC20(WEETH_ADDR).balanceOf(BOB);

        assertGt(balanceAfter, balanceBefore);
        assertApproxEqAbs(balanceAfter - balanceBefore, amountOut, 1);
    }

    function testSwapWeethToEeth() public {
        uint256 minted = _mintEethToExecutor(1 ether);
        bytes memory wrapData = abi.encodePacked(
            address(etherfiExposed),
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.EethToWeeth,
            true
        );
        uint256 weethAmount = etherfiExposed.swap(minted, wrapData);

        bytes memory unwrapData = abi.encodePacked(
            BOB,
            RestrictTransferFrom.TransferType.None,
            EtherfiDirection.WeethToEeth,
            false
        );

        uint256 balanceBefore = IERC20(EETH_ADDR).balanceOf(BOB);
        uint256 amountOut = etherfiExposed.swap(weethAmount, unwrapData);
        uint256 balanceAfter = IERC20(EETH_ADDR).balanceOf(BOB);

        assertGt(balanceAfter, balanceBefore);
        assertApproxEqAbs(balanceAfter - balanceBefore, amountOut, 1);
    }
}

contract TychoRouterForEtherfiTest is TychoRouterTestSetup {
    function getForkBlock() public pure override returns (uint256) {
        return 24332199;
    }

    function testSingleEtherfiUnwrapIntegration() public {
        // weeth -> (unwrap) -> eeth -> (RedemptionManager) -> eth
        IERC20 weeth = IERC20(WEETH_ADDR);
        deal(WEETH_ADDR, BOB, 1 ether);
        uint256 balanceBefore = BOB.balance;

        vm.startPrank(BOB);
        IERC20(WEETH_ADDR).approve(tychoRouterAddr, type(uint256).max);

        bytes memory callData = loadCallDataFromFile(
            "test_sequential_encoding_strategy_etherfi_unwrap_weeth"
        );
        (bool success,) = tychoRouterAddr.call(callData);

        uint256 balanceAfter = BOB.balance;

        assertTrue(success, "Call Failed");
        assertEq(IERC20(WEETH_ADDR).balanceOf(tychoRouterAddr), 0);
        assertGt(balanceAfter, balanceBefore);
    }

    function testSingleEtherfiWrapIntegration() public {
        // eth -> (deposit) -> eeth -> (wrap) -> weeth
        IERC20 weeth = IERC20(WEETH_ADDR);
        deal(BOB, 1 ether);
        uint256 balanceBefore = weeth.balanceOf(BOB);

        vm.startPrank(BOB);

        bytes memory callData = loadCallDataFromFile(
            "test_sequential_encoding_strategy_etherfi_wrap_eeth"
        );
        (bool success,) = tychoRouterAddr.call{value: 1 ether}(callData);

        uint256 balanceAfter = weeth.balanceOf(BOB);

        assertTrue(success, "Call Failed");
        assertEq(IERC20(WEETH_ADDR).balanceOf(tychoRouterAddr), 0);
        assertGt(balanceAfter, balanceBefore);
    }
}
