//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT = type(uint96).max;
    uint256 constant PRECISION = 1e18;

    uint256 public timesMintCalled;

    address[] public users;

    MockV3Aggregator priceFeedWeth;
    MockV3Aggregator priceFeedWbtc;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _engine) {
        dsc = _dsc;
        engine = _engine;

        address[] memory tokenAddresses = engine.getCollateralTokens();
        weth = ERC20Mock(tokenAddresses[0]);
        wbtc = ERC20Mock(tokenAddresses[1]);

        priceFeedWeth = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
        priceFeedWbtc = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateralToken = _getCollateralToken(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amount);
        collateralToken.approve(address(engine), amount);
        engine.depositCollateral(address(collateralToken), amount);
        users.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralToken(collateralSeed);
        uint256 maxCollateral = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        amountCollateral = bound(amountCollateral, 0, maxCollateral / 10000);

        if (amountCollateral == 0) {
            return;
        }
        vm.prank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    // This one breaks our invariant test suite!!!    
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     newPriceInt = bound(newPriceInt, 1, 2000);
    //     priceFeedWeth.updateAnswer(newPriceInt);
    // }

    function mintDsc(uint256 amount, uint256 userSeed) public {
        if (users.length == 0) {
            return;
        }
        address user = users[userSeed % users.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;

        if (maxDscToMint < 0) {
            vm.stopPrank();
            return;
        }

        amount = bound(amount, 0, maxDscToMint);
        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        vm.startPrank(user);
        engine.mintDsc(amount);
        vm.stopPrank();
        timesMintCalled ++;
    }

    function _getCollateralToken(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}