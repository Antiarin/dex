// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OrderBook is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum OrderType {
        LIMIT,
        MARKET
    }

    struct Order {
        uint256 orderId;
        address maker;
        IERC20 tokenA;
        IERC20 tokenB;
        uint256 amountA;
        uint256 amountB;
        uint256 remainingA;
        uint256 remainingB;
        bool isActive;
        uint256 expiry;
        OrderType orderType;
        AggregatorV3Interface priceFeedA;
        AggregatorV3Interface priceFeedB;
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public userOrders;

    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 expiry,
        OrderType orderType
    );
    event OrderCancelled(uint256 indexed orderId, address indexed maker);
    event OrderFilled(
        uint256 indexed orderId,
        address indexed filler,
        uint256 amountFilled,
        uint256 amountReceived
    );

    constructor() {}

    function getLatestPrice(
        AggregatorV3Interface priceFeed
    ) internal view returns (int) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    function calculateFairAmount(
        AggregatorV3Interface priceFeedA,
        AggregatorV3Interface priceFeedB,
        uint256 amountA
    ) public view returns (uint256) {
        int priceA = getLatestPrice(priceFeedA);
        int priceB = getLatestPrice(priceFeedB);
        require(priceA > 0 && priceB > 0, "Invalid price data");
        uint256 amountB = (amountA * uint256(priceA)) / uint256(priceB);
        return amountB;
    }

    function _validateOrderInputs(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal pure {
        require(
            tokenA != address(0) && tokenB != address(0),
            "Invalid token address"
        );
        require(
            amountA > 0 && amountB > 0,
            "Amounts must be greater than zero"
        );
    }

    function _calculateAdjustedAmountB(
        OrderType orderType,
        uint256 amountA,
        uint256 amountB,
        AggregatorV3Interface priceFeedA,
        AggregatorV3Interface priceFeedB
    ) internal view returns (uint256) {
        return
            orderType == OrderType.LIMIT
                ? amountB
                : calculateFairAmount(priceFeedA, priceFeedB, amountA);
    }

     function _storeNewOrder(
        address maker,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 adjustedAmountB,
        uint256 expiry,
        OrderType orderType,
        address priceFeedAAddress,
        address priceFeedBAddress
    ) internal returns (uint256) {
        uint256 orderId = nextOrderId++;

        orders[orderId] = Order({
            orderId: orderId,
            maker: maker,
            tokenA: IERC20(tokenA),
            tokenB: IERC20(tokenB),
            amountA: amountA,
            amountB: adjustedAmountB,
            remainingA: amountA,
            remainingB: adjustedAmountB,
            isActive: true,
            expiry: expiry,
            orderType: orderType,
            priceFeedA: AggregatorV3Interface(priceFeedAAddress),
            priceFeedB: AggregatorV3Interface(priceFeedBAddress)
        });

        userOrders[maker].push(orderId);

        return orderId;
    }

    function createOrder(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 expiry,
        OrderType orderType,
        address priceFeedAAddress,
        address priceFeedBAddress
    ) external nonReentrant returns (uint256) {
        _validateOrderInputs(tokenA, tokenB, amountA, amountB);

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);

        uint256 adjustedAmountB = _calculateAdjustedAmountB(
            orderType,
            amountA,
            amountB,
            AggregatorV3Interface(priceFeedAAddress),
            AggregatorV3Interface(priceFeedBAddress)
        );

        uint256 orderId = _storeNewOrder(
            msg.sender,
            tokenA,
            tokenB,
            amountA,
            adjustedAmountB,
            expiry,
            orderType,
            priceFeedAAddress,
            priceFeedBAddress
        );

        emit OrderCreated(
            orderId,
            msg.sender,
            tokenA,
            tokenB,
            amountA,
            adjustedAmountB,
            expiry,
            orderType
        );
        return orderId;
    }

    function cancelOrder(uint256 orderId) external nonReentrant {
        require(orders[orderId].orderId != 0, "Order does not exist");
        Order storage order = orders[orderId];
        require(
            order.maker == msg.sender,
            "Only the maker can cancel the order"
        );
        require(order.isActive, "Order is already cancelled or filled");

        order.isActive = false;
        order.tokenA.safeTransfer(order.maker, order.remainingA);

        emit OrderCancelled(orderId, msg.sender);
    }

    function fillOrder(
        uint256 orderId,
        uint256 amountToFill
    ) external nonReentrant {
        require(orders[orderId].orderId != 0, "Order does not exist");
        Order storage order = orders[orderId];
        require(order.isActive, "Order is not active");
        require(
            order.expiry == 0 || order.expiry > block.timestamp,
            "Order has expired"
        );
        require(
            amountToFill > 0 && amountToFill <= order.remainingA,
            "Insufficient order amount"
        );

        uint256 amountToReceive = (amountToFill * order.remainingB) /
            order.remainingA;
        order.remainingA -= amountToFill;
        order.remainingB -= amountToReceive;

        order.tokenB.safeTransferFrom(msg.sender, order.maker, amountToReceive);
        order.tokenA.safeTransfer(msg.sender, amountToFill);

        if (order.remainingA == 0) {
            order.isActive = false;
        }

        emit OrderFilled(orderId, msg.sender, amountToFill, amountToReceive);
    }

    function getUserOrders(
        address user
    ) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    function getOrderDetails(
        uint256 orderId
    ) external view returns (Order memory) {
        require(orders[orderId].orderId != 0, "Order does not exist");
        return orders[orderId];
    }
}