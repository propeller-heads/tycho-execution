// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "../src/executors/UniswapV2Executor.sol";
import "./Constants.sol";
import "./mock/MockERC20.sol";
import "@src/TychoRouter.sol";
import {WETH} from "../lib/permit2/lib/solmate/src/tokens/WETH.sol";
import {Permit2TestHelper} from "./Permit2TestHelper.sol";

contract TychoRouterExposed is TychoRouter {
    constructor(address _permit2, address weth) TychoRouter(_permit2, weth) {}

    function wrapETH(uint256 amount) external payable {
        return _wrapETH(amount);
    }

    function unwrapETH(uint256 amount) external {
        return _unwrapETH(amount);
    }
}

contract TychoRouterTestSetup is Constants, Permit2TestHelper {
    TychoRouterExposed tychoRouter;
    address tychoRouterAddr;
    UniswapV2Executor public usv2Executor;
    MockERC20[] tokens;

    function setUp() public {
        uint256 forkBlock = 21817316;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);

        vm.startPrank(ADMIN);
        tychoRouter = deployRouter();
        deployDummyContract();
        vm.stopPrank();

        address[] memory executors = deployExecutors();
        vm.startPrank(EXECUTOR_SETTER);
        tychoRouter.setExecutors(executors);
        vm.stopPrank();

        vm.startPrank(BOB);
        tokens.push(new MockERC20("Token A", "A"));
        tokens.push(new MockERC20("Token B", "B"));
        tokens.push(new MockERC20("Token C", "C"));
        vm.stopPrank();
    }

    function deployRouter() public returns (TychoRouterExposed) {
        tychoRouter = new TychoRouterExposed(PERMIT2_ADDRESS, WETH_ADDR);
        tychoRouterAddr = address(tychoRouter);
        tychoRouter.grantRole(keccak256("FUND_RESCUER_ROLE"), FUND_RESCUER);
        tychoRouter.grantRole(keccak256("PAUSER_ROLE"), PAUSER);
        tychoRouter.grantRole(keccak256("UNPAUSER_ROLE"), UNPAUSER);
        tychoRouter.grantRole(
            keccak256("EXECUTOR_SETTER_ROLE"), EXECUTOR_SETTER
        );
        return tychoRouter;
    }

    function deployExecutors() public returns (address[] memory) {
        address factoryV2 = USV2_FACTORY_ETHEREUM;
        address factoryV3 = USV3_FACTORY_ETHEREUM;
        address factoryPancakeV3 = PANCAKESWAPV3_DEPLOYER_ETHEREUM;
        bytes32 initCodeV2 = USV2_POOL_CODE_INIT_HASH;
        bytes32 initCodeV3 = USV3_POOL_CODE_INIT_HASH;
        bytes32 initCodePancakeV3 = PANCAKEV3_POOL_CODE_INIT_HASH;
        address poolManagerAddress = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        address ekuboCore = 0xe0e0e08A6A4b9Dc7bD67BCB7aadE5cF48157d444;

        IPoolManager poolManager = IPoolManager(poolManagerAddress);
        usv2Executor =
            new UniswapV2Executor(factoryV2, initCodeV2, PERMIT2_ADDRESS);

        address[] memory executors = new address[](1);
        executors[0] = address(usv2Executor);
        return executors;
    }

    /**
     * @dev Mints tokens to the given address
     * @param amount The amount of tokens to mint
     * @param to The address to mint tokens to
     */
    function mintTokens(uint256 amount, address to) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            // slither-disable-next-line calls-loop
            tokens[i].mint(to, amount);
        }
    }

    function pleEncode(bytes[] memory data)
        public
        pure
        returns (bytes memory encoded)
    {
        for (uint256 i = 0; i < data.length; i++) {
            encoded = bytes.concat(
                encoded,
                abi.encodePacked(bytes2(uint16(data[i].length)), data[i])
            );
        }
    }

    function encodeSequentialSwap(address executor, bytes memory protocolData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(executor, protocolData);
    }

    function encodeUniswapV2Swap(
        address tokenIn,
        address target,
        address receiver,
        bool zero2one,
        TokenTransfer.TransferType transferType
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(tokenIn, target, receiver, zero2one, transferType);
    }
}
