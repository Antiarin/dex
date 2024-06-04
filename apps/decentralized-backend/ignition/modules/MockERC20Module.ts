import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const ERC20MockModule = buildModule("ERC20MockModule", (m) => {
  const name = m.getParameter<string>("name", "MockToken");
  const symbol = m.getParameter<string>("symbol", "MCK");
  const decimals = m.getParameter<number>("decimals", 18);

  const erc20Mock = m.contract("ERC20Mock", [name, symbol, decimals]);

  return { erc20Mock };
});

export default ERC20MockModule;
