// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./MockERC20.sol";

/**
 * @title MockMaliciousToken
 * @notice A malicious ERC20 token for testing attack vectors
 * @dev This token can be configured to revert transfers, return false, or manipulate balances
 */
contract MockMaliciousToken is MockERC20 {
    bool public shouldRevert;
    bool public shouldReturnFalse;
    bool public shouldManipulateBalance;
    uint256 public manipulatedBalance;
    
    mapping(address => bool) public blockedAddresses;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) MockERC20(name, symbol, decimals, 0) {}
    
    /**
     * @notice Configure the token to revert on transfers
     */
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
    
    /**
     * @notice Configure the token to return false on transfers
     */
    function setShouldReturnFalse(bool _shouldReturnFalse) external {
        shouldReturnFalse = _shouldReturnFalse;
    }
    
    /**
     * @notice Configure the token to manipulate balance queries
     */
    function setShouldManipulateBalance(bool _shouldManipulate, uint256 _manipulatedBalance) external {
        shouldManipulateBalance = _shouldManipulate;
        manipulatedBalance = _manipulatedBalance;
    }
    
    /**
     * @notice Block specific addresses from receiving tokens
     */
    function blockAddress(address account, bool blocked) external {
        blockedAddresses[account] = blocked;
    }
    
    /**
     * @notice Malicious transfer function
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldRevert) {
            revert("MaliciousToken: Transfer reverted");
        }
        
        if (shouldReturnFalse) {
            return false;
        }
        
        if (blockedAddresses[to]) {
            revert("MaliciousToken: Address blocked");
        }
        
        return super.transfer(to, amount);
    }
    
    /**
     * @notice Malicious transferFrom function
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldRevert) {
            revert("MaliciousToken: TransferFrom reverted");
        }
        
        if (shouldReturnFalse) {
            return false;
        }
        
        if (blockedAddresses[to] || blockedAddresses[from]) {
            revert("MaliciousToken: Address blocked");
        }
        
        return super.transferFrom(from, to, amount);
    }
    
    /**
     * @notice Malicious balanceOf function
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (shouldManipulateBalance) {
            return manipulatedBalance;
        }
        
        return super.balanceOf(account);
    }
}

/**
 * @title MockReentrantToken
 * @notice A token that attempts reentrancy attacks during transfers
 */
contract MockReentrantToken is MockERC20 {
    address public target;
    bool public reentrancyEnabled;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) MockERC20(name, symbol, decimals, 0) {}
    
    /**
     * @notice Set the target contract for reentrancy attacks
     */
    function setTarget(address _target) external {
        target = _target;
    }
    
    /**
     * @notice Enable/disable reentrancy attacks
     */
    function setReentrancyEnabled(bool _enabled) external {
        reentrancyEnabled = _enabled;
    }
    
    /**
     * @notice Reentrancy attack during transfer
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);
        
        if (reentrancyEnabled && target != address(0)) {
            // Attempt reentrancy attack by calling back into the target
            try IReentrancyTarget(target).attackVector() {
                // Attack succeeded
            } catch {
                // Attack failed, which is expected due to reentrancy guard
            }
        }
        
        return success;
    }
    
    /**
     * @notice Reentrancy attack during transferFrom
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        
        if (reentrancyEnabled && target != address(0)) {
            // Attempt reentrancy attack
            try IReentrancyTarget(target).attackVector() {
                // Attack succeeded
            } catch {
                // Attack failed
            }
        }
        
        return success;
    }
}

/**
 * @title IReentrancyTarget
 * @notice Interface for reentrancy attack targets
 */
interface IReentrancyTarget {
    function attackVector() external;
}

/**
 * @title MockFeeOnTransferToken
 * @notice A token that charges fees on transfers to test handling of tokens with transfer fees
 */
contract MockFeeOnTransferToken is MockERC20 {
    uint256 public transferFeeNumerator = 1; // 0.1% default fee
    uint256 public transferFeeDenominator = 1000;
    address public feeRecipient;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address _feeRecipient
    ) MockERC20(name, symbol, decimals, 0) {
        feeRecipient = _feeRecipient;
    }
    
    /**
     * @notice Set transfer fee (numerator/denominator)
     */
    function setTransferFee(uint256 numerator, uint256 denominator) external {
        require(denominator > 0, "Invalid denominator");
        require(numerator <= denominator, "Fee too high");
        transferFeeNumerator = numerator;
        transferFeeDenominator = denominator;
    }
    
    /**
     * @notice Transfer with fee deduction
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        uint256 fee = (amount * transferFeeNumerator) / transferFeeDenominator;
        uint256 transferAmount = amount - fee;
        
        _transfer(owner, to, transferAmount);
        
        if (fee > 0 && feeRecipient != address(0)) {
            _transfer(owner, feeRecipient, fee);
        }
        
        return true;
    }
    
    /**
     * @notice TransferFrom with fee deduction
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        
        uint256 fee = (amount * transferFeeNumerator) / transferFeeDenominator;
        uint256 transferAmount = amount - fee;
        
        _transfer(from, to, transferAmount);
        
        if (fee > 0 && feeRecipient != address(0)) {
            _transfer(from, feeRecipient, fee);
        }
        
        return true;
    }
}

/**
 * @title MockDeflatinaryToken
 * @notice A token that burns a percentage of tokens on each transfer (deflationary mechanism)
 */
contract MockDeflatinaryToken is MockERC20 {
    uint256 public burnRate = 50; // 0.5% burn rate (50/10000)
    uint256 public constant BURN_RATE_DENOMINATOR = 10000;
    
    event Burn(uint256 amount);
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) MockERC20(name, symbol, decimals, 0) {}
    
    /**
     * @notice Set burn rate (basis points)
     */
    function setBurnRate(uint256 _burnRate) external {
        require(_burnRate <= BURN_RATE_DENOMINATOR, "Burn rate too high");
        burnRate = _burnRate;
    }
    
    /**
     * @notice Transfer with burn mechanism
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        uint256 burnAmount = (amount * burnRate) / BURN_RATE_DENOMINATOR;
        uint256 transferAmount = amount - burnAmount;
        
        if (burnAmount > 0) {
            _burn(owner, burnAmount);
            emit Burn(burnAmount);
        }
        
        _transfer(owner, to, transferAmount);
        return true;
    }
    
    /**
     * @notice TransferFrom with burn mechanism
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        
        uint256 burnAmount = (amount * burnRate) / BURN_RATE_DENOMINATOR;
        uint256 transferAmount = amount - burnAmount;
        
        if (burnAmount > 0) {
            _burn(from, burnAmount);
            emit Burn(burnAmount);
        }
        
        _transfer(from, to, transferAmount);
        return true;
    }
}