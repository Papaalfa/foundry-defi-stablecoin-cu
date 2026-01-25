// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";
import { Handler } from "./Handler.t.sol";

contract InvariantsTests is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    DeployDSC deployer;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        // targetContract(address(engine));
        handler = new Handler(dsc, engine);
        targetContract(address(handler));
    }

    function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = ERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = ERC20(wbtc).balanceOf(address(engine));

        uint256 totalWethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 totalWbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        uint256 totalCollateralValue = totalWethValue + totalWbtcValue;

        console.log("Total Supply DSC:", totalSupply);
        console.log("Total Collateral Value USD:", totalCollateralValue);
        console.log("Total WETH Value USD:", totalWethValue);
        console.log("Total WBTC Value USD:", totalWbtcValue);
        console.log("Times Mint Called:", handler.timesMintCalled());

        assertGe(totalCollateralValue, totalSupply);
    }

    function invariant_gettersCantRevert() public view {
        engine.getCollateralBalanceOfUser(address(0), address(0));
        engine.getCollateralTokens();
        engine.getCollateralDeposited(address(0), address(0));
        engine.getAccountInformation(address(0));
        engine.getUsdValue(address(0), 0);
        engine.getDscMinted(address(0));
    }
}