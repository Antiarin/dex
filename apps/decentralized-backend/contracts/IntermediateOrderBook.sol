// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract IntermediateOrderBook is ReentrancyGuard {
    using SafeERC20 for ERC20;

    enum OrderType { LIMIT, MARKET }
    enum Side { BUY, SELL }

    struct Order {
        uint256 orderId;
        address maker;
        ERC20 tokenA;
        ERC20 tokenB;
        uint256 initialAmountA;
        uint256 initialAmountB;
        uint256 remainingAmountA;
        uint256 remainingAmountB;
        bool isActive;
        uint256 expiry;
        OrderType orderType;
        Side side;
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;
    mapping(address => uint256[]) public userOrders;
    Order[] public buyOrders;
    Order[] public sellOrders;

    event OrderCreated(uint256 indexed orderId, address indexed maker, address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 expiry, OrderType orderType, Side side);
    event OrderCancelled(uint256 indexed orderId, address indexed maker);
    event OrderFilled(uint256 indexed orderId, address indexed filler, uint256 amountFilled, uint256 amountReceived);

    function createOrder(address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 expiry, OrderType orderType, Side side) external nonReentrant returns (uint256) {
        require(tokenA != address(0) && tokenB != address(0), "Invalid token address");
        require(amountA > 0, "AmountA must be greater than zero");
        require(expiry == 0 || expiry > block.timestamp, "Invalid expiry time");

        ERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);

        uint256 orderId = nextOrderId++;
        Order memory order = Order({
            orderId: orderId,
            maker: msg.sender,
            tokenA: ERC20(tokenA),
            tokenB: ERC20(tokenB),
            initialAmountA: amountA,
            initialAmountB: amountB,
            remainingAmountA: amountA,
            remainingAmountB: amountB,
            isActive: true,
            expiry: expiry,
            orderType: orderType,
            side: side
        });

        orders[orderId] = order;
        userOrders[msg.sender].push(orderId);

        if (side == Side.BUY) {
            buyOrders.push(order);
        } else {
            sellOrders.push(order);
        }

        emit OrderCreated(orderId, msg.sender, tokenA, tokenB, amountA, amountB, expiry, orderType, side);
        return orderId;
    }

    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.maker == msg.sender, "Only the maker can cancel the order");
        require(order.isActive, "Order is already cancelled or filled");

        order.isActive = false;
        order.tokenA.safeTransfer(order.maker, order.remainingAmountA);

        emit OrderCancelled(orderId, msg.sender);
    }

    function fillOrder(uint256 orderId, uint256 amountToFill) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.isActive, "Order is not active");
        require(order.expiry == 0 || order.expiry > block.timestamp, "Order has expired");
        require(amountToFill > 0, "Amount to fill must be greater than 0");
        require(amountToFill <= order.remainingAmountA, "Amount exceeds the available tokens");

        uint256 amountToReceive = (amountToFill * order.remainingAmountB) / order.remainingAmountA;

        order.remainingAmountA -= amountToFill;
        order.remainingAmountB -= amountToReceive;

        order.tokenB.safeTransferFrom(msg.sender, order.maker, amountToReceive);
        order.tokenA.safeTransfer(msg.sender, amountToFill);

        if (order.remainingAmountA == 0) {
            order.isActive = false;
        }

        emit OrderFilled(orderId, msg.sender, amountToFill, amountToReceive);
    }

    function fillMarketOrder(Side side, uint256 amountToFill) external nonReentrant {
        require(amountToFill > 0, "Amount to fill must be greater than 0");

        if (side == Side.BUY) {
            _fillMarketOrder(amountToFill, sellOrders, Side.SELL);
        } else {
            _fillMarketOrder(amountToFill, buyOrders, Side.BUY);
        }
    }

    function _fillMarketOrder(uint256 amountToFill, Order[] storage orderBook, Side side) internal {
        uint256 amountFilled = 0;
        uint256 amountReceived = 0;

        for (uint256 i = 0; i < orderBook.length && amountToFill > 0; i++) {
            Order storage order = orderBook[i];

            if (!order.isActive || order.expiry <= block.timestamp) {
                continue;
            }

            uint256 fillAmount = (amountToFill <= order.remainingAmountA) ? amountToFill : order.remainingAmountA;
            uint256 receiveAmount = (fillAmount * order.initialAmountB) / order.initialAmountA;

            if (fillAmount > 0) {
                amountToFill -= fillAmount;
                amountFilled += fillAmount;
                amountReceived += receiveAmount;

                order.remainingAmountA -= fillAmount;
                order.remainingAmountB -= receiveAmount;

                if (order.remainingAmountA == 0) {
                    order.isActive = false;
                }

                if (side == Side.SELL) {
                    order.tokenB.safeTransferFrom(msg.sender, order.maker, receiveAmount);
                    order.tokenA.safeTransfer(msg.sender, fillAmount);
                } else {
                    order.tokenA.safeTransferFrom(msg.sender, order.maker, fillAmount);
                    order.tokenB.safeTransfer(msg.sender, receiveAmount);
                }

                emit OrderFilled(order.orderId, msg.sender, fillAmount, receiveAmount);
            }
        }

        require(amountFilled > 0, "No matching orders found");
    }

    function getUserOrders(address user) external view returns (uint256[] memory) {
        return userOrders[user];
    }

    function getOrderDetails(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }
}
