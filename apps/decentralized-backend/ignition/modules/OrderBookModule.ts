import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const OrderBookModule = buildModule("OrderBookModule", (m) => {
  const orderBook = m.contract("OrderBook");

  return { orderBook };
});

export default OrderBookModule;
