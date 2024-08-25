//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    TokenConfig,
    TokenType,
    LiquidityManagement,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PoolHelpers, InitializationConfig } from "./PoolHelpers.sol";
import { ScaffoldHelpers, console } from "./ScaffoldHelpers.sol";
import { VeBALFeeDiscountHook } from "../contracts/hooks/VeBALFeeDiscountHook.sol";
import { ConstantProductFactory } from "../contracts/pools/ConstantProductFactory.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

/**
 * @title Deploy Weighted
 * @notice Deploys a factory and hooks contract and then deploys, registers, and initializes a weighted pool
 */
contract DeployWeighted is PoolHelpers, ScaffoldHelpers {
    function run(address token1, address token2, address veBAL) external {
        // Set the pool configurations
        InitializationConfig memory initConfig = getInitializationConfig(token1, token2);

        // Start creating the transactions
        uint256 deployerPrivateKey = getDeployerPrivateKey();
        vm.startBroadcast(deployerPrivateKey);

        // Deploy a weighted pool factory contract
        WeightedPoolFactory factory = new WeightedPoolFactory(IVault(vault), 365 days, "Factory v1", " Pool v1");
        console.log("Constant Product Factory deployed at: %s", address(factory));

        // Deploy a hooks contract
        VeBALFeeDiscountHook poolHooksContract = new VeBALFeeDiscountHook(
            IVault(vault),
            address(factory),
            address(router),
            IERC20(veBAL)
        );
        console.log("VeBALFeeDiscountHook deployed at address: %s", address(poolHooksContract));

        // Deploy a pool and register it with the vault
        address pool = factory.create(
            "50/50 Weighted Pool", // string name
            "50-50-WP", // string symbol
            getTokenConfigs(token1, token2), // TokenConfig[] tokenConfigs
            getNormailzedWeights(), // uint256[] normalizedWeights
            getRoleAccounts(), // PoolRoleAccounts roleAccounts
            0.03e18, // uint256 swapFeePercentage (3%)
            address(poolHooksContract), // address poolHooksContract
            true, //bool enableDonation
            false, // bool disableUnbalancedLiquidity
            keccak256(abi.encode(block.number)) // bytes32 salt
        );
        console.log("Weighted Pool deployed at: %s", pool);

        // Approve Permit2 contract to spend tokens on behalf of deployer
        approveSpenderOnToken(address(permit2), initConfig.tokens);

        // Approve Router contract to spend tokens using Permit2
        approveSpenderOnPermit2(address(router), initConfig.tokens);

        // Seed the pool with initial liquidity
        router.initialize(
            pool,
            initConfig.tokens,
            initConfig.exactAmountsIn,
            initConfig.minBptAmountOut,
            initConfig.wethIsEth,
            initConfig.userData
        );
        console.log("Weighted Pool initialized successfully!");
        vm.stopBroadcast();
    }

    /**
     * @notice TokenConfig encapsulates the data required for the Vault to support a token of the given type.
     * For STANDARD tokens, the rate provider address must be 0, and paysYieldFees must be false.
     * All WITH_RATE tokens need a rate provider, and may or may not be yield-bearing.
     */
    function getTokenConfigs(address token1, address token2) internal pure returns (TokenConfig[] memory tokenConfigs) {
        tokenConfigs = new TokenConfig[](2); // An array of descriptors for the tokens the pool will manage
        tokenConfigs[0] = TokenConfig({ // Make sure to have proper token order (alphanumeric)
            token: IERC20(token1),
            tokenType: TokenType.STANDARD, // STANDARD or WITH_RATE
            rateProvider: IRateProvider(address(0)), // The rate provider for a token (see further documentation above)
            paysYieldFees: false // Flag indicating whether yield fees should be charged on this token
        });
        tokenConfigs[1] = TokenConfig({ // Make sure to have proper token order (alphanumeric)
            token: IERC20(token2),
            tokenType: TokenType.STANDARD, // STANDARD or WITH_RATE
            rateProvider: IRateProvider(address(0)), // The rate provider for a token (see further documentation above)
            paysYieldFees: false // Flag indicating whether yield fees should be charged on this token
        });
        sortTokenConfig(tokenConfigs);
    }

    function getNormailzedWeights() internal pure returns (uint256[] memory normalizedWeights) {
        normalizedWeights = new uint256[](2);
        normalizedWeights[0] = uint256(50e16);
        normalizedWeights[1] = uint256(50e16);
    }

    function getRoleAccounts() internal pure returns (PoolRoleAccounts memory roleAccounts) {
        roleAccounts = PoolRoleAccounts({
            pauseManager: address(0), // Account empowered to pause/unpause the pool (or 0 to delegate to governance)
            swapFeeManager: address(0), // Account empowered to set static swap fees for a pool (or 0 to delegate to goverance)
            poolCreator: address(0) // Account empowered to set the pool creator fee percentage
        });
    }

    /**
     * @dev Set the pool initialization configurations here
     * @notice This is where the amounts of tokens to seed the pool with initial liquidity are set
     */
    function getInitializationConfig(
        address token1,
        address token2
    ) internal pure returns (InitializationConfig memory config) {
        IERC20[] memory tokens = new IERC20[](2); // Array of tokens to be used in the pool
        tokens[0] = IERC20(token1);
        tokens[1] = IERC20(token2);
        uint256[] memory exactAmountsIn = new uint256[](2); // Exact amounts of tokens to be added, sorted in token alphanumeric order
        exactAmountsIn[0] = 50e18; // amount of token1 to send during pool initialization
        exactAmountsIn[1] = 50e18; // amount of token2 to send during pool initialization
        uint256 minBptAmountOut = 49e18; // Minimum amount of pool tokens to be received
        bool wethIsEth = false; // If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
        bytes memory userData = bytes(""); // Additional (optional) data required for adding initial liquidity

        config = InitializationConfig({
            tokens: InputHelpers.sortTokens(tokens),
            exactAmountsIn: exactAmountsIn,
            minBptAmountOut: minBptAmountOut,
            wethIsEth: wethIsEth,
            userData: userData
        });
    }
}