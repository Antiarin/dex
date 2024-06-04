import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MockV3AggregatorModule = buildModule("MockV3AggregatorModule", (m) => {
  const decimals = m.getParameter<number>("decimals", 18);
  const initialAnswer = m.getParameter<number>("initialAnswer", 2000 * 1e8); // Initial answer with 8 decimals

  const mockV3Aggregator = m.contract("MockV3Aggregator", [decimals, initialAnswer]);

  return { mockV3Aggregator };
});

export default MockV3AggregatorModule;
