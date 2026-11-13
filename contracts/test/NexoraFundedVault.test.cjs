const { expect } = require("chai");
const { ethers } = require("hardhat");

const U = (v) => ethers.parseUnits(String(v), 6);

describe("NexoraFundedVault - mock tUSDT only", function () {
  let token, vault, admin, operator, alice, bob, carol, dave, outsider;

  beforeEach(async function () {
    [admin, operator, alice, bob, carol, dave, outsider] = await ethers.getSigners();
    token = await ethers.deployContract("MockUSDT");
    await token.waitForDeployment();
    vault = await ethers.deployContract("NexoraFundedVault", [
      await token.getAddress(),
      admin.address,
      operator.address
    ]);
    await vault.waitForDeployment();
    for (const s of [admin, operator, alice, bob, carol, dave, outsider]) {
      await token.mint(s.address, U(100000));
      await token.connect(s).approve(await vault.getAddress(), U(100000));
    }
  });

  async function chain() {
    await vault.connect(alice).deposit(U(200), admin.address);
    await vault.connect(bob).deposit(U(200), alice.address);
    await vault.connect(carol).deposit(U(200), bob.address);
    await vault.connect(dave).deposit(U(200), carol.address);
  }

  it("requires 10 USDT initial deposit; enforces 50,000 maximum", async function () {
    await expect(vault.connect(alice).deposit(U(9), admin.address)).to.be.reverted;
    await vault.connect(alice).deposit(U(200), admin.address);
    await expect(vault.connect(alice).deposit(U(50000), admin.address)).to.be.reverted;
    expect(await vault.principalOf(alice.address)).to.equal(U(200));
    expect(await vault.totalPrincipal()).to.equal(U(200));
    expect(await vault.solvent()).to.equal(true);
  });

  it("withdraws principal without needing admin approval", async function () {
    await vault.connect(alice).deposit(U(200), ethers.ZeroAddress);
    const before = await token.balanceOf(alice.address);
    await vault.connect(alice).withdrawPrincipal(U(175));
    expect((await token.balanceOf(alice.address)) - before).to.equal(U(175));
    expect(await vault.principalOf(alice.address)).to.equal(U(25));
    expect(await vault.totalPrincipal()).to.equal(U(25));
    expect(await vault.solvent()).to.equal(true);
  });

  it("distributes 15/7/3 ONLY from operator-funded profit, without reducing principal", async function () {
    await chain();
    const before = await token.balanceOf(operator.address);
    await vault.connect(operator).settleFundedProfit(dave.address, U(100));

    expect(before - await token.balanceOf(operator.address)).to.equal(U(125));
    expect(await vault.availableCredit(dave.address)).to.equal(U(100));
    expect(await vault.availableCredit(carol.address)).to.equal(U(15));
    expect(await vault.availableCredit(bob.address)).to.equal(U(7));
    expect(await vault.availableCredit(alice.address)).to.equal(U(3));
    expect(await vault.totalCredits()).to.equal(U(125));
    expect(await vault.totalPrincipal()).to.equal(U(800));
    expect(await vault.solvent()).to.equal(true);

    await vault.connect(dave).withdrawCredit(U(100));
    await vault.connect(carol).withdrawCredit(U(15));
    expect(await vault.solvent()).to.equal(true);
    expect(await vault.totalPrincipal()).to.equal(U(800));
  });

  it("requires exact new funding and never draws principal for settlements", async function () {
    await chain();
    await expect(vault.connect(outsider).settleFundedProfit(dave.address, U(100))).to.be.reverted;
    await token.connect(operator).approve(await vault.getAddress(), U(1));
    await expect(vault.connect(operator).settleFundedProfit(dave.address, U(100))).to.be.reverted;
    expect(await vault.totalCredits()).to.equal(0n);
    expect(await vault.totalPrincipal()).to.equal(U(800));
  });

  it("referrals need a registered ancestor and cannot be changed later", async function () {
    await expect(vault.connect(alice).register(outsider.address)).to.be.reverted;
    await vault.connect(alice).register(admin.address);
    await expect(vault.connect(alice).register(bob.address)).to.be.reverted;
    await expect(vault.connect(alice).deposit(U(20), bob.address)).to.be.reverted;
    expect(await vault.sponsor(alice.address)).to.equal(admin.address);
  });

  it("pausing disables new deposits/settlements, but NOT withdrawals", async function () {
    await vault.connect(alice).deposit(U(100), ethers.ZeroAddress);
    await vault.connect(operator).settleFundedProfit(alice.address, U(10));
    await vault.pause();
    await expect(vault.connect(bob).deposit(U(10), ethers.ZeroAddress)).to.be.reverted;
    await expect(vault.connect(operator).settleFundedProfit(alice.address, U(10))).to.be.reverted;
    await vault.connect(alice).withdrawCredit(U(10));
    await vault.connect(alice).withdrawPrincipal(U(100));
    expect(await vault.solvent()).to.equal(true);
    await vault.unpause();
    await vault.connect(bob).deposit(U(10), ethers.ZeroAddress);
  });

  it("does not attribute missing referral levels or mint unfunded credit", async function () {
    await vault.connect(alice).deposit(U(100), ethers.ZeroAddress);
    const before = await token.balanceOf(operator.address);
    await vault.connect(operator).settleFundedProfit(alice.address, U(10));
    expect(before - await token.balanceOf(operator.address)).to.equal(U(10));
    expect(await vault.totalCredits()).to.equal(U(10));
  });
});
