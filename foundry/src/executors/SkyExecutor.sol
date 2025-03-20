// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "@interfaces/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error SkyExecutor__InvalidDataLength();
error SkyExecutor__UnsupportedComponentType();
error SkyExecutor__OperationFailed();

interface ISkyVault {
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);
}

interface ISkyConverter {
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver
    ) external returns (uint256 amountOut);
}

interface ISkyPSM {
    function swapWithFee(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        uint24 fee
    ) external returns (uint256 amountOut);
}

contract SkyExecutor is IExecutor {
    using SafeERC20 for IERC20;

    // Component types
    uint8 private constant COMPONENT_TYPE_VAULT = 1;
    uint8 private constant COMPONENT_TYPE_CONVERTER = 2;
    uint8 private constant COMPONENT_TYPE_PSM = 3;

    function swap(
        uint256 amountIn,
        bytes calldata data
    ) external payable returns (uint256 calculatedAmount) {
        // Decode the common parameters from data
        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            address componentAddress,
            address receiver,
            uint8 componentType,
            bytes memory extraData
        ) = _decodeData(data);

        // Transfer tokens from caller to this contract
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve tokens for the component to use
        tokenIn.approve(componentAddress, amountIn);

        // Process based on component type
        if (componentType == COMPONENT_TYPE_VAULT) {
            // Handle Vault components (sDAI, sUSDS)
            bool isDeposit = extraData.length > 0 && uint8(extraData[0]) == 1;
            calculatedAmount = _handleVaultOperation(
                componentAddress,
                address(tokenIn),
                address(tokenOut),
                amountIn,
                receiver,
                isDeposit
            );
        } else if (componentType == COMPONENT_TYPE_CONVERTER) {
            // Handle Converter components (DAI-USDS, MKR-SKY)
            calculatedAmount = _handleConverterOperation(
                componentAddress,
                address(tokenIn),
                address(tokenOut),
                amountIn,
                receiver
            );
        } else if (componentType == COMPONENT_TYPE_PSM) {
            // Handle PSM components with optional fee
            uint24 fee = 0;
            if (extraData.length >= 3) {
                // Extract fee - correctly handle memory bytes for bytes3
                bytes3 feeBytes;
                assembly {
                    feeBytes := mload(add(extraData, 32))
                }
                fee = uint24(feeBytes);
            }
            calculatedAmount = _handlePSMOperation(
                componentAddress,
                address(tokenIn),
                address(tokenOut),
                amountIn,
                receiver,
                fee
            );
        } else {
            revert SkyExecutor__UnsupportedComponentType();
        }

        // If there are any unused tokens, send them back
        uint256 remainingBalance = tokenIn.balanceOf(address(this));
        if (remainingBalance > 0) {
            tokenIn.safeTransfer(msg.sender, remainingBalance);
        }

        return calculatedAmount;
    }

    function _handleVaultOperation(
        address vault,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        bool isDeposit
    ) internal returns (uint256 amountOut) {
        ISkyVault vaultContract = ISkyVault(vault);

        if (isDeposit) {
            // Deposit: tokenIn is the base token (DAI), tokenOut is the vault token (sDAI)
            amountOut = vaultContract.deposit(amountIn, receiver);
        } else {
            // Withdraw: tokenIn is the vault token (sDAI), tokenOut is the base token (DAI)
            amountOut = vaultContract.withdraw(
                amountIn,
                receiver,
                address(this)
            );
        }

        if (amountOut == 0) {
            revert SkyExecutor__OperationFailed();
        }

        return amountOut;
    }

    function _handleConverterOperation(
        address converter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver
    ) internal returns (uint256 amountOut) {
        ISkyConverter converterContract = ISkyConverter(converter);
        amountOut = converterContract.swapExactInput(
            tokenIn,
            tokenOut,
            amountIn,
            receiver
        );

        if (amountOut == 0) {
            revert SkyExecutor__OperationFailed();
        }

        return amountOut;
    }

    function _handlePSMOperation(
        address psm,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        uint24 fee
    ) internal returns (uint256 amountOut) {
        ISkyPSM psmContract = ISkyPSM(psm);
        amountOut = psmContract.swapWithFee(
            tokenIn,
            tokenOut,
            amountIn,
            receiver,
            fee
        );

        if (amountOut == 0) {
            revert SkyExecutor__OperationFailed();
        }

        return amountOut;
    }

    function _decodeData(
        bytes calldata data
    )
        internal
        pure
        returns (
            IERC20 tokenIn,
            IERC20 tokenOut,
            address componentAddress,
            address receiver,
            uint8 componentType,
            bytes memory extraData
        )
    {
        // Minimum data length is 80 bytes (20+20+20+20)
        if (data.length < 80) {
            revert SkyExecutor__InvalidDataLength();
        }

        tokenIn = IERC20(address(bytes20(data[0:20])));
        tokenOut = IERC20(address(bytes20(data[20:40])));
        componentAddress = address(bytes20(data[40:60]));
        receiver = address(bytes20(data[60:80]));

        // Determine component type based on component address
        componentType = _determineComponentType(componentAddress);

        // Extract any extra data (if present)
        if (data.length > 80) {
            extraData = data[80:];
        } else {
            extraData = new bytes(0);
        }
    }

    function _determineComponentType(
        address componentAddress
    ) internal pure returns (uint8) {
        // sDAI Vault and sUSDS Vault
        if (
            componentAddress == 0x83F20F44975D03b1b09e64809B757c47f942BEeA || // sDAI Vault
            componentAddress == 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD // sUSDS Vault
        ) {
            return COMPONENT_TYPE_VAULT;
        }
        // DAI-USDS Converter and MKR-SKY Converter
        else if (
            componentAddress == 0x3225737a9Bbb6473CB4a45b7244ACa2BeFdB276A || // DAI-USDS Converter
            componentAddress == 0xBDcFCA946b6CDd965f99a839e4435Bcdc1bc470B // MKR-SKY Converter
        ) {
            return COMPONENT_TYPE_CONVERTER;
        }
        // DAI Lite PSM and USDS PSM Wrapper
        else if (
            componentAddress == 0xf6e72Db5454dd049d0788e411b06CfAF16853042 || // DAI Lite PSM
            componentAddress == 0xA188EEC8F81263234dA3622A406892F3D630f98c // USDS PSM Wrapper
        ) {
            return COMPONENT_TYPE_PSM;
        }
        // Default to converter for unknown components
        else {
            return COMPONENT_TYPE_CONVERTER;
        }
    }
}
