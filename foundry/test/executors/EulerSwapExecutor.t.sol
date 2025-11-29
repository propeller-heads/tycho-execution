// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@src/executors/EulerSwapExecutor.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {Constants} from "../Constants.sol";

contract EulerSwapExecutorExposed is EulerSwapExecutor {
    constructor(address _periphery) EulerSwapExecutor(_periphery) {}

    function decodeParams(bytes calldata data)
        external
        pure
        returns (
            IERC20 inToken,
            IERC20 outToken,
            address target,
            address receiver
        )
    {
        return _decodeData(data);
    }
}

contract FakeUniswapV2Pool {
    address public token0;
    address public token1;

    constructor(address _tokenA, address _tokenB) {
        token0 = _tokenA < _tokenB ? _tokenA : _tokenB;
        token1 = _tokenA < _tokenB ? _tokenB : _tokenA;
    }
}

contract EulerSwapExecutorTest is Test, Constants {
    using SafeERC20 for IERC20;

    address public constant EULERSWAP_PERIPHERY =
        0x813D74E832b3d9E9451d8f0E871E877edf2a5A5f;
    address public constant USDC_USDT_POOL =
        0x2bFED8dBEb8e6226a15300AC77eE9130E52410fE;

    EulerSwapExecutorExposed eulerswapExposed;
    IERC20 USDC = IERC20(USDC_ADDR);
    IERC20 USDT = IERC20(USDT_ADDR);

    function setUp() public {
        uint256 forkBlock = 21986045;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);
        eulerswapExposed = new EulerSwapExecutorExposed(EULERSWAP_PERIPHERY);
    }

    function testDecodeParams() public view {
        bytes memory params =
            abi.encodePacked(USDC_ADDR, USDT_ADDR, address(3), address(4));

        (IERC20 tokenIn, IERC20 tokenOut, address target, address receiver) =
            eulerswapExposed.decodeParams(params);

        assertEq(address(tokenIn), address(USDC));
        assertEq(address(tokenOut), address(USDT));
        assertEq(target, address(3));
        assertEq(receiver, address(4));
    }

    function testDecodeParamsInvalidDataLength() public {
        bytes memory invalidParams =
            abi.encodePacked(USDC_ADDR, USDT_ADDR, address(3));

        vm.expectRevert(
            EulerSwapExecutor.EulerSwapExecutor__InvalidDataLength.selector
        );
        eulerswapExposed.decodeParams(invalidParams);
    }

    function testSwap() public {
        uint256 amountIn = 5e6;
        bytes memory protocolData =
            abi.encodePacked(USDC_ADDR, USDT_ADDR, USDC_USDT_POOL, BOB);

        uint256 balanceBefore = USDT.balanceOf(BOB);

        deal(USDC_ADDR, address(eulerswapExposed), amountIn);
        eulerswapExposed.swap(amountIn, protocolData);

        assertGt(USDT.balanceOf(BOB), balanceBefore);
    }
}
