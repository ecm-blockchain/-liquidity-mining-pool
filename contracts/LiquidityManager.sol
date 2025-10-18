// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPoolManager {
    function recordLiquidityAdded(uint256 poolId, uint256 ecmAmount, uint256 usdtAmount) external;
}

/// @title LiquidityManager - Manages Uniswap V2 Liquidity Operations
/// @notice Receives tokens explicitly from PoolManager and adds liquidity to Uniswap V2
/// @dev Isolated contract to limit blast-radius - does NOT access PoolManager internals
contract LiquidityManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================
    
    /// @notice Uniswap V2 Router address
    IUniswapV2Router02 public immutable uniswapRouter;
    
    /// @notice PoolManager contract for tracking callbacks
    IPoolManager public poolManager;
    
    /// @notice Treasury address for LP tokens
    address public treasury;
    
    /// @notice Track total liquidity added per token pair
    mapping(address => mapping(address => uint256)) public totalLiquidityAdded;
    
    // ============================================
    // STRUCTS
    // ============================================
    
    /// @notice Parameters for adding liquidity
    struct AddLiquidityParams {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
        uint256 deadline;
    }
    
    // ============================================
    // EVENTS
    // ============================================
    
    event LiquidityAdded(
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity,
        address indexed to
    );
    
    event LiquidityRemoved(
        address indexed tokenA,
        address indexed tokenB,
        uint256 liquidity,
        uint256 amountA,
        uint256 amountB,
        address indexed to
    );
    
    event LPTokenWithdrawn(
        address indexed lpToken,
        uint256 amount,
        address indexed to
    );
    
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    
    event PoolManagerUpdated(address indexed oldPoolManager, address indexed newPoolManager);
    
    event TokensRecovered(
        address indexed token,
        uint256 amount,
        address indexed to
    );

    // ============================================
    // ERRORS
    // ============================================
    
    error InvalidRouter();
    error InvalidTreasury();
    error InvalidAmount();
    error InvalidToken();
    error InvalidAddress();
    error InsufficientBalance();
    error SlippageExceeded();
    error DeadlineExpired();
    error ApprovalFailed();

    // ============================================
    // CONSTRUCTOR
    // ============================================
    
    /// @notice Initializes the LiquidityManager contract
    /// @param _uniswapRouter Address of Uniswap V2 Router
    /// @param _treasury Address to receive LP tokens
    constructor(address _uniswapRouter, address _treasury) Ownable(msg.sender) {
        if (_uniswapRouter == address(0)) revert InvalidRouter();
        if (_treasury == address(0)) revert InvalidTreasury();
        
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        treasury = _treasury;
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================
    
    /// @notice Adds liquidity to Uniswap V2 pool
    /// @dev Only callable by owner (multisig recommended)
    /// @param params AddLiquidityParams struct containing all parameters
    /// @return amountA Actual amount of tokenA added
    /// @return amountB Actual amount of tokenB added
    /// @return liquidity Amount of LP tokens minted
    function addLiquidity(AddLiquidityParams calldata params) 
        external 
        onlyOwner 
        nonReentrant 
        returns (
            uint256 amountA, 
            uint256 amountB, 
            uint256 liquidity
        ) 
    {
        (amountA, amountB, liquidity) = _addLiquidity(params, 0, address(0));
    }

    /// @notice Adds liquidity to Uniswap V2 pool with PoolManager tracking
    /// @dev Only callable by owner (multisig recommended)
    /// @param params AddLiquidityParams struct containing all parameters
    /// @param poolId Pool ID for tracking (if 0, no callback)
    /// @param ecmToken Address of ECM token to identify which is ECM vs USDT
    /// @return amountA Actual amount of tokenA added
    /// @return amountB Actual amount of tokenB added
    /// @return liquidity Amount of LP tokens minted
    function addLiquidityWithTracking(
        AddLiquidityParams calldata params,
        uint256 poolId,
        address ecmToken
    ) 
        external 
        onlyOwner 
        nonReentrant 
        returns (
            uint256 amountA, 
            uint256 amountB, 
            uint256 liquidity
        ) 
    {
        (amountA, amountB, liquidity) = _addLiquidity(params, poolId, ecmToken);
    }

    /// @notice Internal function to add liquidity
    /// @param params AddLiquidityParams struct
    /// @param poolId Pool ID for tracking (if 0, no callback)
    /// @param ecmToken Address of ECM token (if address(0), no callback)
    /// @return amountA Actual amount of tokenA added
    /// @return amountB Actual amount of tokenB added
    /// @return liquidity Amount of LP tokens minted
    function _addLiquidity(
        AddLiquidityParams calldata params,
        uint256 poolId,
        address ecmToken
    )
        internal
        returns (
            uint256 amountA, 
            uint256 amountB, 
            uint256 liquidity
        )
    {
        // Validation
        if (params.tokenA == address(0) || params.tokenB == address(0)) revert InvalidToken();
        if (params.amountADesired == 0 || params.amountBDesired == 0) revert InvalidAmount();
        if (params.deadline < block.timestamp) revert DeadlineExpired();
        
        address recipient = params.to == address(0) ? treasury : params.to;
        
        // Check balances
        if (IERC20(params.tokenA).balanceOf(address(this)) < params.amountADesired) revert InsufficientBalance();
        if (IERC20(params.tokenB).balanceOf(address(this)) < params.amountBDesired) revert InsufficientBalance();
        
        // Approve router (safe approve pattern for tokens like USDT)
        _safeApprove(IERC20(params.tokenA), address(uniswapRouter), params.amountADesired);
        _safeApprove(IERC20(params.tokenB), address(uniswapRouter), params.amountBDesired);
        
        // Add liquidity
        (amountA, amountB, liquidity) = uniswapRouter.addLiquidity(
            params.tokenA,
            params.tokenB,
            params.amountADesired,
            params.amountBDesired,
            params.amountAMin,
            params.amountBMin,
            recipient,
            params.deadline
        );
        
        // Reset approvals to 0 for safety
        _safeApprove(IERC20(params.tokenA), address(uniswapRouter), 0);
        _safeApprove(IERC20(params.tokenB), address(uniswapRouter), 0);
        
        // Track liquidity added
        totalLiquidityAdded[params.tokenA][params.tokenB] += liquidity;
        
        // Callback to PoolManager if tracking is enabled
        if (poolId > 0 && ecmToken != address(0) && address(poolManager) != address(0)) {
            // Determine which amount is ECM and which is USDT
            bool isECMTokenA = params.tokenA == ecmToken;
            uint256 ecmAmount = isECMTokenA ? amountA : amountB;
            uint256 usdtAmount = isECMTokenA ? amountB : amountA;
            
            poolManager.recordLiquidityAdded(poolId, ecmAmount, usdtAmount);
        }
        
        emit LiquidityAdded(params.tokenA, params.tokenB, amountA, amountB, liquidity, recipient);
    }

    /// @notice Removes liquidity from Uniswap V2 pool
    /// @dev Only callable by owner (multisig recommended)
    /// @param tokenA Address of first token
    /// @param tokenB Address of second token
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountAMin Minimum amount of tokenA to receive
    /// @param amountBMin Minimum amount of tokenB to receive
    /// @param to Address to receive tokens
    /// @param deadline Unix timestamp deadline for transaction
    /// @return amountA Amount of tokenA received
    /// @return amountB Amount of tokenB received
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        onlyOwner
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        if (tokenA == address(0) || tokenB == address(0)) revert InvalidToken();
        if (liquidity == 0) revert InvalidAmount();
        if (to == address(0)) to = treasury;
        if (deadline < block.timestamp) revert DeadlineExpired();
        
        // Note: LP tokens should be sent to this contract first
        // Approve router to spend LP tokens
        address pair = _getPairAddress(tokenA, tokenB);
        _safeApprove(IERC20(pair), address(uniswapRouter), liquidity);
        
        // Remove liquidity
        (amountA, amountB) = uniswapRouter.removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
        
        // Reset approval
        _safeApprove(IERC20(pair), address(uniswapRouter), 0);
        
        emit LiquidityRemoved(tokenA, tokenB, liquidity, amountA, amountB, to);
    }

    /// @notice Withdraws LP tokens to specified address
    /// @dev Used to move LP tokens to treasury or other destination
    /// @param lpToken Address of LP token
    /// @param amount Amount to withdraw
    /// @param to Recipient address
    function withdrawLP(
        address lpToken,
        uint256 amount,
        address to
    ) external onlyOwner nonReentrant {
        if (lpToken == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        if (to == address(0)) to = treasury;
        
        uint256 balance = IERC20(lpToken).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();
        
        IERC20(lpToken).safeTransfer(to, amount);
        
        emit LPTokenWithdrawn(lpToken, amount, to);
    }

    /// @notice Emergency function to recover any ERC20 tokens
    /// @dev Should only be used for mistakenly sent tokens
    /// @param token Token address to recover
    /// @param amount Amount to recover
    /// @param to Recipient address
    function recoverTokens(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidToken();
        if (amount == 0) revert InvalidAmount();
        if (to == address(0)) to = treasury;
        
        IERC20(token).safeTransfer(to, amount);
        
        emit TokensRecovered(token, amount, to);
    }

    /// @notice Updates the treasury address
    /// @param _treasury New treasury address
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert InvalidTreasury();
        
        address oldTreasury = treasury;
        treasury = _treasury;
        
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /// @notice Sets the PoolManager contract for tracking callbacks
    /// @param _poolManager Address of PoolManager contract
    function setPoolManager(address _poolManager) external onlyOwner {
        address oldPoolManager = address(poolManager);
        poolManager = IPoolManager(_poolManager);
        
        emit PoolManagerUpdated(oldPoolManager, _poolManager);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================
    
    /// @notice Gets the balance of a token held by this contract
    /// @param token Token address
    /// @return balance Token balance
    function getTokenBalance(address token) external view returns (uint256 balance) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Gets the total liquidity added for a token pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return liquidity Total liquidity added
    function getTotalLiquidityAdded(address tokenA, address tokenB) 
        external 
        view 
        returns (uint256 liquidity) 
    {
        return totalLiquidityAdded[tokenA][tokenB];
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================
    
    /// @notice Safe approve pattern for tokens like USDT
    /// @dev Sets approval to 0 first, then to desired amount
    /// @param token Token to approve
    /// @param spender Spender address
    /// @param amount Amount to approve
    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        
        if (currentAllowance != 0) {
            token.forceApprove(spender, 0);
        }
        
        if (amount != 0) {
            token.forceApprove(spender, amount);
        }
    }

    /// @notice Gets the pair address for two tokens
    /// @dev Uses Uniswap V2 Factory to get the pair address
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @return pair Pair address
    function _getPairAddress(address tokenA, address tokenB) internal view returns (address pair) {
        address factory = uniswapRouter.factory();
        pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        
        if (pair == address(0)) revert InvalidToken(); // Pair doesn't exist
    }

    // ============================================
    // RECEIVE FUNCTION
    // ============================================
    
    /// @notice Allows contract to receive ETH (if needed for WETH operations)
    receive() external payable {}
}
