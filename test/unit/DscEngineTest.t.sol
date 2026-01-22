// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
// import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { Test, console } from "forge-std/Test.sol";

contract DSCEngineTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    // error DSCEngine__TokenAndPriceFeedAddressesAmountsDontMatch();

    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;
    
    address public user = makeAddr("user");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant STARTING_LIQUIDATOR_BALANCE = 10 ether;
    uint256 public constant TOO_MUCH_TO_MINT = 10_001 ether;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();

        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(liquidator, STARTING_LIQUIDATOR_BALANCE);
        // ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    function testConstructorArraysDoNotMatch() public {
        address[] memory tokenAddresses = new address[](2);
        address[] memory priceFeedAddresses = new address[](1);

        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;

        priceFeedAddresses[0] = ethUsdPriceFeed;

        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
    }

    function testConstructorSucceedsWithEmptyArrays() public {
        address[] memory emptyTokens = new address[](0);
        address[] memory emptyFeeds = new address[](0);

        DSCEngine engineEmpty = new DSCEngine(emptyTokens, emptyFeeds, address(dsc));

        // Should deploy successfully
        assertTrue(address(engineEmpty) != address(0));

        // Any token should be rejected as not allowed (indirectly verifies no tokens were added)
        vm.expectRevert(); // Will revert on call to address(0) price feed or NotAllowedToken
        engineEmpty.getUsdValue(weth, 1e18);
    }


    /*//////////////////////////////////////////////////////////////
                              PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $2000/ETH = $30,000e18
        uint256 expectedUsd = 30_000e18;
        uint256 usdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = engine.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

     function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", user, 100e18);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(randToken)));
        engine.depositCollateral(address(randToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        uint256 expectedDepositedAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, AMOUNT_COLLATERAL);
    }

    /*//////////////////////////////////////////////////////////////
                             MINT TESTS
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testRevertsIfMintZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(user);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userDscBalance = dsc.balanceOf(user);
        assertEq(userDscBalance, AMOUNT_TO_MINT);
    }

    function testRevertsIfMintBreaksHealthFactor() public depositedCollateral {
        // 10 ETH collateral ≈ $20,000
        // Threshold: 50% → max mintable ≈ $10,000 worth of DSC
        // Trying to mint $20,000 worth would break health factor
        uint256 tooMuchToMint = TOO_MUCH_TO_MINT;

        vm.startPrank(user);
        vm.expectRevert();
        engine.mintDsc(tooMuchToMint);
        vm.stopPrank();
    }

    function testHealthFactorImprovesAfterBurning() public depositedCollateralAndMintedDsc {
        uint256 initialHealthFactor = engine.getHealthFactor(user);
        assertGt(initialHealthFactor, MIN_HEALTH_FACTOR);

        vm.startPrank(user);
        dsc.approve(address(engine), AMOUNT_TO_MINT / 2);
        engine.burnDsc(AMOUNT_TO_MINT / 2);
        vm.stopPrank();

        uint256 finalHealthFactor = engine.getHealthFactor(user);
        assertGt(finalHealthFactor, initialHealthFactor);
    }

    /*//////////////////////////////////////////////////////////////
                            BURN & REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(dsc.balanceOf(user), 0);
        assertEq(engine.getDscMinted(user), 0);
    }

    function testCanRedeemCollateral() public depositedCollateral {
        uint256 redeemAmount = AMOUNT_COLLATERAL / 2;

        vm.startPrank(user);
        engine.redeemCollateral(weth, redeemAmount);
        uint256 remaining = engine.getCollateralDeposited(user, weth);
        vm.stopPrank();
        
        assertEq(remaining, AMOUNT_COLLATERAL - redeemAmount);
    }

    function testRevertsIfRedeemBreaksHealthFactor() public depositedCollateralAndMintedDsc {
        // User has 10 ETH collateral (~$20k), minted 100 DSC (~$100)
        // Health factor is very high. But if we had minted near max, this would break.

        // Instead, simulate a high debt scenario
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__breaksHealthFactor.selector, 10));
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL - 1); // Leave very little
        // vm.expectRevert(); // Should revert due to health factor drop
        // engine.redeemCollateral(weth, 1);
        vm.stopPrank();
    }

    function testRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        uint256 burnAmount = AMOUNT_TO_MINT / 2;
        uint256 redeemAmount = AMOUNT_COLLATERAL / 2;

        vm.startPrank(user);
        dsc.approve(address(engine), burnAmount);
        engine.redeemCollateralForDsc(weth, redeemAmount, burnAmount);
        vm.stopPrank();

        assertEq(dsc.balanceOf(user), AMOUNT_TO_MINT - burnAmount);
        assertEq(engine.getCollateralDeposited(user, weth), AMOUNT_COLLATERAL - redeemAmount);
    }

    /*//////////////////////////////////////////////////////////////
                           LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCantLiquidateHealthyUser() public depositedCollateralAndMintedDsc {
        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, user, 1);
        vm.stopPrank();
    }
}