// // SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// import { Test } from "forge-std/Test.sol";
// import { StdInvariant } from "forge-std/StdInvariant.sol";
// import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
// import { DSCEngine } from "../../src/DSCEngine.sol";
// import { HelperConfig } from "../../script/HelperConfig.s.sol";
// import { DeployDSC } from "../../script/DeployDSC.s.sol";
// import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";

// contract OpenInvariantsTests is StdInvariant, Test {
//     DecentralizedStableCoin dsc;
//     DSCEngine engine;
//     HelperConfig helperConfig;
//     DeployDSC deployer;
//     address weth;
//     address wbtc;

//     function setUp() public {
//         deployer = new DeployDSC();
//         (dsc, engine, helperConfig) = deployer.run();
//         (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
//         targetContract(address(engine));
//     }

//     function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = ERC20(weth).balanceOf(address(engine));
//         uint256 totalWbtcDeposited = ERC20(wbtc).balanceOf(address(engine));

//         uint256 totalWethValue = engine.getUsdValue(weth, totalWethDeposited);
//         uint256 totalWbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

//         uint256 totalCollateralValue = totalWethValue + totalWbtcValue;

//         assertGe(totalCollateralValue, totalSupply);
//     }

// }
