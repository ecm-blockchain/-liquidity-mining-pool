// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title MockUniswapV2Router - Mock Uniswap V2 Router for testing
/// @notice Provides getAmountOut and getAmountIn calculations
contract MockUniswapV2Router {
    
    /// @notice Calculate amount out based on reserves (with 0.3% fee)
    /// @param amountIn Input amount
    /// @param reserveIn Input token reserve
    /// @param reserveOut Output token reserve
    /// @return amountOut Output amount
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        
        amountOut = numerator / denominator;
    }
    
    /// @notice Calculate amount in required for desired amount out
    /// @param amountOut Desired output amount
    /// @param reserveIn Input token reserve
    /// @param reserveOut Output token reserve
    /// @return amountIn Required input amount
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn) {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        
        amountIn = (numerator / denominator) + 1;
    }
}
