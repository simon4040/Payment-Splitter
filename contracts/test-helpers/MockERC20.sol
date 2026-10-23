// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Minimal ERC-20 mock for Foundry tests.
///      Supports mint, burn, configurable decimals, and a toggleable
///      "revert on transfer" mode to exercise try/catch dust paths.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @dev When true, transfer() and transferFrom() revert — used to
    ///      simulate a broken recipient and exercise the dust accumulation path.
    bool public revertOnTransfer;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    // ── Admin helpers ────────────────────────────────────────────────────────

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /// @dev Toggle whether transfer() / transferFrom() revert.
    function setRevertOnTransfer(bool flag) external {
        revertOnTransfer = flag;
    }

    // ── ERC-20 core ──────────────────────────────────────────────────────────

    function transfer(address to, uint256 amount) external returns (bool) {
        if (revertOnTransfer) revert("MockERC20: transfer reverted");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (revertOnTransfer) revert("MockERC20: transfer reverted");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}
