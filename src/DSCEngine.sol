// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Patrick Collins
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // To bring 1e8 to 1e18
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1 * 1e18 = 1.0

    mapping(address token => address priceFeed) private sPriceFeeds; // token address -> price feed address
    mapping(address user => mapping(address token => uint256 amount)) private sCollateralDeposited; // user address -> (token address -> amount deposited)
    mapping(address user => uint256 amountDscMinted) private sDscMinted; // user address -> amount of DSC minted
    address[] private sCollateralTokens;

    DecentralizedStableCoin private immutable I_DSC;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (sPriceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
        
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeedAddresses, 
        address dscAddress
    ) {
        // USD price feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            sPriceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            sCollateralTokens.push(tokenAddresses[i]);
        }
        I_DSC = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc() external payable {
        //
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*
     * @notice Following CEI pattern
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        // Checks (happening in modifiers)
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        // Effects
        sCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // Interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral() external payable {
        //
    }

    /*
    * @notice Following CEI pattern
    * @param amountDscToMint: The amount of decentralized stabelcoin you want to mint
    * @notice You must have more collateral value than the minimum threshold after minting
    */
    function mintDsc(
        uint256 amountDscToMint
    ) 
        external 

        //Checks (happening in modifiers)
        moreThanZero(amountDscToMint) 
        nonReentrant 
    {        
        // Effects
        sDscMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        // Interactions

    }

    function redeemCollateralforDsc() external payable {
        //
    }

    function burnDsc() external payable {
        //
    }

    function liquidate() external payable {
        //
    }

    function getHealthFactor() external pure returns (uint256) {
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                   PRIVATE & INTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getAccountInformation(
        address user
    ) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = sDscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
        return (totalDscMinted, collateralValueInUsd);
    }

    /*
     * @notice Returns the health factor of a user, given the total DSC minted and collateral value in USD
     * @dev  A health factor > MIN_HEALTH_FACTOR means you're healthy
     *       A health factor < MIN_HEALTH_FACTOR means you're unhealthy / liquidatable
     * @param totalDscMinted: The total amount of DSC minted by the user
     * @param collateralValueInUsd: The total USD value of the collateral deposited by the user
     * @return The health factor of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total USD minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(sPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //
    }

    /*//////////////////////////////////////////////////////////////
                    PUBLIC & EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    )
        external
        view
        returns (uint256)
    {
        return _getUsdValue(token, amount);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < sCollateralTokens.length; index++) {
            address token = sCollateralTokens[index];
            uint256 amount = sCollateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

}