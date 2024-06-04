import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("OrderBook contract", function () {
  async function deployOrderBooksFixture() {
    const OrderBook = await ethers.getContractFactory("OrderBook");
    const [owner, addr1] = await ethers.getSigners();

    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    const tokenA = await ERC20Mock.deploy("Token A", "TKA", 18);
    const tokenB = await ERC20Mock.deploy("Token B", "TKB", 18);

    await tokenA.waitForDeployment();
    await tokenB.waitForDeployment();

    const mintAmount = ethers.parseUnits("1000", 18);
    await tokenA.mint(owner.address, mintAmount);
    await tokenB.mint(owner.address, mintAmount);
    await tokenA.mint(addr1.address, mintAmount);
    await tokenB.mint(addr1.address, mintAmount);

    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const priceFeedA = await MockV3Aggregator.deploy(18, ethers.parseUnits("1", 18));
    const priceFeedB = await MockV3Aggregator.deploy(18, ethers.parseUnits("2", 18));

    await priceFeedA.waitForDeployment();
    await priceFeedB.waitForDeployment();

    const orderBook = await OrderBook.deploy();
    await orderBook.waitForDeployment();

    return { orderBook, tokenA, tokenB, owner, addr1, priceFeedA, priceFeedB };
  }

  describe("Create Order", function () {
    it("Should create an order successfully", async function () {
      const { orderBook, tokenA, tokenB, owner, priceFeedA, priceFeedB } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);
      const amountB = ethers.parseUnits("20", 18);
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      const orderType = 0;

      await tokenA.connect(owner).approve(orderBook.target, amountA);

      await expect(orderBook.createOrder(
        tokenA.target,
        tokenB.target,
        amountA,
        amountB,
        expiry,
        orderType,
        priceFeedA.target,
        priceFeedB.target
      ))
        .to.emit(orderBook, "OrderCreated")
        .withArgs(0, owner.address, tokenA.target, tokenB.target, amountA, amountB, expiry, orderType);

      const order = await orderBook.orders(0);
      expect(order.maker).to.equal(owner.address);
      expect(order.tokenA).to.equal(tokenA.target);
      expect(order.tokenB).to.equal(tokenB.target);
      expect(order.amountA).to.equal(amountA);
      expect(order.amountB).to.equal(amountB);
      expect(order.remainingA).to.equal(amountA);
      expect(order.remainingB).to.equal(amountB);
      expect(order.isActive).to.equal(true);
      expect(order.expiry).to.equal(expiry);
      expect(order.orderType).to.equal(orderType);
    });

    it("Should adjust amountB for MARKET orders based on price feed", async function () {
      const { orderBook, tokenA, tokenB, owner, priceFeedA, priceFeedB } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);
      const priceA = ethers.parseUnits("1", 18);
      const priceB = ethers.parseUnits("2", 18);
      const expectedAmountB = amountA * (priceA) / (priceB);
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      const orderType = 1;

      await tokenA.connect(owner).approve(orderBook.target, amountA);

      await expect(orderBook.createOrder(
        tokenA.target,
        tokenB.target,
        amountA,
        expectedAmountB,
        expiry,
        orderType,
        priceFeedA.target,
        priceFeedB.target
      ))
        .to.emit(orderBook, "OrderCreated");

      const order = await orderBook.orders(0);
      expect(order.maker).to.equal(owner.address);
      expect(order.tokenA).to.equal(tokenA.target);
      expect(order.tokenB).to.equal(tokenB.target);
      expect(order.amountA).to.equal(amountA);
      expect(order.amountB).to.equal(expectedAmountB);
      expect(order.remainingA).to.equal(amountA);
      expect(order.remainingB).to.equal(expectedAmountB);
      expect(order.isActive).to.equal(true);
      expect(order.expiry).to.equal(expiry);
      expect(order.orderType).to.equal(orderType);
    });
  });

  describe("Cancel Order", function () {
    it("Should cancel an order successfully", async function () {
      const { orderBook, tokenA, tokenB, owner, priceFeedA, priceFeedB } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);
      const amountB = ethers.parseUnits("20", 18);
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      const orderType = 0;

      await tokenA.connect(owner).approve(orderBook.target, amountA);

      await orderBook.createOrder(
        tokenA.target,
        tokenB.target,
        amountA,
        amountB,
        expiry,
        orderType,
        priceFeedA.target,
        priceFeedB.target
      );

      await expect(orderBook.cancelOrder(0))
        .to.emit(orderBook, "OrderCancelled")
        .withArgs(0, owner.address);

      const order = await orderBook.orders(0);
      expect(order.isActive).to.equal(false);
    });

    it("Should revert if a non-maker tries to cancel an order", async function () {
      const { orderBook, tokenA, tokenB, owner, addr1, priceFeedA, priceFeedB } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);
      const amountB = ethers.parseUnits("20", 18);
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      const orderType = 0;

      await tokenA.connect(owner).approve(orderBook.target, amountA);

      await orderBook.createOrder(
        tokenA.target,
        tokenB.target,
        amountA,
        amountB,
        expiry,
        orderType,
        priceFeedA.target,
        priceFeedB.target
      );

      await expect(orderBook.connect(addr1).cancelOrder(0)).to.be.revertedWith("Only the maker can cancel the order");
    });

    it("Should revert if the order is already cancelled or filled", async function () {
      const { orderBook, tokenA, tokenB, owner, priceFeedA, priceFeedB } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);
      const amountB = ethers.parseUnits("20", 18);
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      const orderType = 0;

      await tokenA.connect(owner).approve(orderBook.target, amountA);

      await orderBook.createOrder(
        tokenA.target,
        tokenB.target,
        amountA,
        amountB,
        expiry,
        orderType,
        priceFeedA.target,
        priceFeedB.target
      );

      await orderBook.cancelOrder(0);

      await expect(orderBook.cancelOrder(0)).to.be.revertedWith("Order is already cancelled or filled");
    });

    it("Should revert if the order does not exist", async function () {
      const { orderBook } = await loadFixture(deployOrderBooksFixture);

      await expect(orderBook.cancelOrder(999)).to.be.revertedWith("Order does not exist");
    });
  });

  describe("Fill Order", function () {
    it("Should fill an order successfully", async function () {
      const { orderBook, tokenA, tokenB, owner, addr1, priceFeedA, priceFeedB } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);
      const amountB = ethers.parseUnits("20", 18);
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      const orderType = 0;

      await tokenA.connect(owner).approve(orderBook.target, amountA);

      const tx = await orderBook.createOrder(
        tokenA.target,
        tokenB.target,
        amountA,
        amountB,
        expiry,
        orderType,
        priceFeedA.target,
        priceFeedB.target
      );
      await tx.wait();

      await tokenB.connect(owner).transfer(addr1.address, amountB);

      await tokenB.connect(addr1).approve(orderBook.target, amountB);

      const fillTx = await orderBook.connect(addr1).fillOrder(0, amountA);
      await expect(fillTx).to.emit(orderBook, "OrderFilled").withArgs(0, addr1.address, amountA, amountB);

      const order = await orderBook.orders(0);
      expect(order.remainingA).to.equal(0);
      expect(order.remainingB).to.equal(0);
      expect(order.isActive).to.equal(false);
    });


    

    it("Should revert if the order is not active", async function () {
      const { orderBook, tokenA, tokenB, owner, addr1, priceFeedA, priceFeedB } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);
      const amountB = ethers.parseUnits("20", 18);
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      const orderType = 0;

      await tokenA.connect(owner).approve(orderBook.target, amountA);

      await orderBook.createOrder(
        tokenA.target,
        tokenB.target,
        amountA,
        amountB,
        expiry,
        orderType,
        priceFeedA.target,
        priceFeedB.target
      );

      await orderBook.cancelOrder(0);

      await expect(orderBook.connect(addr1).fillOrder(0, amountA)).to.be.revertedWith("Order is not active");
    });

    it("Should revert if trying to fill more than available", async function () {
      const { orderBook, tokenA, tokenB, owner, addr1, priceFeedA, priceFeedB } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);
      const amountB = ethers.parseUnits("20", 18);
      const expiry = Math.floor(Date.now() / 1000) + 3600;
      const orderType = 0;

      await tokenA.connect(owner).approve(orderBook.target, amountA);

      await orderBook.createOrder(
        tokenA.target,
        tokenB.target,
        amountA,
        amountB,
        expiry,
        orderType,
        priceFeedA.target,
        priceFeedB.target
      );

      await tokenB.connect(owner).transfer(addr1.address, amountB);

      await tokenB.connect(addr1).approve(orderBook.target, amountB);

      await expect(orderBook.connect(addr1).fillOrder(0, amountA+ethers.parseUnits("1", 18))).to.be.revertedWith("Insufficient order amount");
    });

    it("Should revert if the order does not exist", async function () {
      const { orderBook, addr1 } = await loadFixture(deployOrderBooksFixture);

      const amountA = ethers.parseUnits("10", 18);

      await expect(orderBook.connect(addr1).fillOrder(999, amountA)).to.be.revertedWith("Order does not exist");
    });
  });
});
