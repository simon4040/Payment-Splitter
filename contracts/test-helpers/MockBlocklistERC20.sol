// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev ERC-20 mock whose transfer() can fail per destination, like a USDC
///      blocklist. `blocked[to]` makes transfer/transferFrom revert; `returnFalse[to]`
///      makes transfer return false (non-reverting failure). Used to exercise
///      deferred-payout paths without breaking every other transfer.
contract MockBlocklistERC20 {
    string public name = "Mock Blocklist USDC";
    string public symbol = "mbUSDC";
    uint8 public decimals = 6;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    mapping(address => bool) public blocked;
    mapping(address => bool) public returnFalse;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function setBlocked(address who, bool flag) external {
        blocked[who] = flag;
    }

    function setReturnFalse(address who, bool flag) external {
        returnFalse[who] = flag;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (blocked[to]) revert("blocked");
        if (returnFalse[to]) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (blocked[to]) revert("blocked");
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
