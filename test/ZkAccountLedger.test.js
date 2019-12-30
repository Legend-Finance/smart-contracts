const utils = require('./Utils.js');
const Ffs = require('./ffs/ffs.js');
const ZkAccountLedger = artifacts.require('ZkAccountLedger');
const CEther = artifacts.require('CEtherInterface');
const CErc20 = artifacts.require('CErc20Interface');
const Erc20 = artifacts.require('EIP20Interface');
const DepositEndpoint = artifacts.require('DepositEndpoint');
const PayoutPool = artifacts.require('PayoutPool');


contract('ZkAccountLedger', function ([admin, ...accounts]) {

  let ffs = new Ffs([23, 32, 222, 121], 8, 4, 4);
  let version = "0";

  let n, S, V, salt;
  [n, S, V, salt] = ffs.setup();

  let sign, r, x;
  [sign, r, x] = ffs.initProof(n);

  for (i = 0; i < V.length; i++) {
    V[i] = V[i].toString();
  }
  console.log("n:" + n, "S:" + S, "V:" + V, "sign:" + sign, "r:" + r, "x:" + r, "salt:" + salt);

  beforeEach(async function () {
    this.cEth = await CEther.at("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5");
    this.cErc20 = await CErc20.at("0x39aa39c021dfbae8fac545936693ac917d5e7563"); //cUSDC
    this.erc20 = await Erc20.at("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"); //USDC
    this.payoutPool = await PayoutPool.new();
    this.zkAccountLedger = await ZkAccountLedger.new();
    await this.zkAccountLedger.supportCEther(this.cEth.address);
    await this.zkAccountLedger.supportCErc20(this.cErc20.address, this.erc20.address);
    await this.zkAccountLedger.setLegendPool(accounts[2]);
    await this.zkAccountLedger.setPayoutPool(accounts[4]);
    await this.payoutPool.setMSC(this.zkAccountLedger.address);
    assert(await this.zkAccountLedger.admin() == admin);
  });

  describe('account lifecycle', function () {
    it('should create an account', async function () {
      await this.zkAccountLedger.createAccount("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", accounts[3], n.toString(), V, salt, version);
      let userId = await this.zkAccountLedger.depositEndpoints(0);
      assert(userId != utils.zeroAddress);
      assert(await this.zkAccountLedger.redeemAddress(userId, "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5") == accounts[3]);
    });
    it('should deposit and record eth transfer', async function () {
      await this.zkAccountLedger.createAccount("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await depositEndpoint.sendTransaction({value: utils.toEther("1")});
      let ethBalance = await web3.eth.getBalance(depositEndpointAddress);
      await depositEndpoint.depositLegendEth();
      let legendEthBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5");
      assert(ethBalance.toString() == legendEthBalance.toString());
    });
    it('should deposit and record erc20 transfer', async function () {
      await this.zkAccountLedger.createAccount("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await this.erc20.transfer(depositEndpointAddress, "100", {from: "0x0Bc57B1f2A47bfb031f4F277E82F0E4AE79f1B18"});
      let erc20Balance = await this.erc20.balanceOf(depositEndpointAddress);
      await depositEndpoint.depositLegendErc20(this.erc20.address);
      await this.zkAccountLedger.mintCErc20(this.erc20.address);
      let legendEthBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, this.erc20.address);
      assert(erc20Balance.toString() == legendEthBalance.toString());
    });
    it('should authenticate and withdraw eth', async function () {
      await this.zkAccountLedger.createAccount("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await depositEndpoint.sendTransaction({value: utils.toEther("1")});
      await depositEndpoint.depositLegendEth();
      await this.zkAccountLedger.beginAuthentication(depositEndpointAddress, x.toString());
      await this.zkAccountLedger.createAuthParams(depositEndpointAddress, "0");
      let auth = await this.zkAccountLedger.getAuthParams(depositEndpointAddress, "0");
      a = auth.map(x => x.toNumber());
      let y = await ffs.computeY(r, S, a, n);
      await this.zkAccountLedger.withdrawEth(y.toString(), depositEndpointAddress, "5", "0");
    });
    it('should authenticate and withdraw erc20', async function () {
      await this.zkAccountLedger.createAccount("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await this.erc20.transfer(depositEndpointAddress, "100", {from: "0x0Bc57B1f2A47bfb031f4F277E82F0E4AE79f1B18"});
      let erc20Balance = await this.erc20.balanceOf(depositEndpointAddress);
      await depositEndpoint.depositLegendErc20(this.erc20.address);
      await this.zkAccountLedger.mintCErc20(this.erc20.address);
      await this.zkAccountLedger.beginAuthentication(depositEndpointAddress, x.toString());
      await this.zkAccountLedger.createAuthParams(depositEndpointAddress, "0");
      let auth = await this.zkAccountLedger.getAuthParams(depositEndpointAddress, "0");
      a = auth.map(x => x.toNumber());
      let y = await ffs.computeY(r, S, a, n);
      await this.zkAccountLedger.withdrawErc20(y.toString(), depositEndpointAddress, this.erc20.address, "5", "0");
    });
    it('should reject withdraws without auth', async function () {
      await this.zkAccountLedger.createAccount("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await depositEndpoint.sendTransaction({value: utils.toEther("1")});
      await depositEndpoint.depositLegendEth();
      let a = [1, 0, 0, 1];
      let y = await utils.computeY(r, S, a, n);
      await utils.assertRevert(this.zkAccountLedger.withdrawEth(y.toString(), depositEndpointAddress, 5, "0"));
    });
    it('should eject eth', async function () {
      await this.zkAccountLedger.createAccount("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await depositEndpoint.sendTransaction({value: utils.toEther("1")});
      await depositEndpoint.depositLegendEth();
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await this.zkAccountLedger.returnToRedeemAddressEth(depositEndpointAddress);
      let legendEthBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5");
      assert(legendEthBalance.toString() == "0");
    });
    it('should eject erc20', async function () {
      await this.zkAccountLedger.createAccount("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await this.erc20.transfer(depositEndpointAddress, "100", {from: "0x0Bc57B1f2A47bfb031f4F277E82F0E4AE79f1B18"});
      let erc20Balance = await this.erc20.balanceOf(depositEndpointAddress);
      await depositEndpoint.depositLegendErc20(this.erc20.address);
      await this.zkAccountLedger.mintCErc20(this.erc20.address);
      await this.zkAccountLedger.returnToRedeemAddressErc20(depositEndpointAddress, this.erc20.address);
      let legendBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, this.erc20.address);
      assert(legendBalance.toString() == "0");
    });
    it('should allow multiple auth attempts', async function () {
      await this.zkAccountLedger.createAccount("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await this.zkAccountLedger.adminAddRedeemAddress(depositEndpointAddress, this.cEth.address, accounts[3])
      await this.erc20.transfer(depositEndpointAddress, "100", {from: "0x0Bc57B1f2A47bfb031f4F277E82F0E4AE79f1B18"});
      let erc20Balance = await this.erc20.balanceOf(depositEndpointAddress);
      await depositEndpoint.depositLegendErc20(this.erc20.address);
      await this.zkAccountLedger.mintCErc20(this.erc20.address);
      await this.zkAccountLedger.beginAuthentication(depositEndpointAddress, x.toString());
      await this.zkAccountLedger.createAuthParams(depositEndpointAddress, "0");
      let auth = await this.zkAccountLedger.getAuthParams(depositEndpointAddress, "0");
      await this.zkAccountLedger.beginAuthentication(depositEndpointAddress, x.toString());
      await this.zkAccountLedger.createAuthParams(depositEndpointAddress, "1");
      let auth2 = await this.zkAccountLedger.getAuthParams(depositEndpointAddress, "1");
      a = auth.map(x => x.toNumber());
      a2 = auth2.map(x => x.toNumber());
      let y = await utils.computeY(r, S, a, n);
      let y2 = await utils.computeY(r, S, a2, n);
      await this.zkAccountLedger.withdrawEth(y.toString(), depositEndpointAddress, "5", "0");
      let legendEthBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
      console.log(legendEthBalance.toString());
      await this.zkAccountLedger.withdrawEth(y2.toString(), depositEndpointAddress, "5", "0");
    })
  });

  describe('asset support', function () {
    it('should accept ether sent directly', async function () {
      await utils.assertRevert(this.zkAccountLedger.sendTransaction({value: utils.toEther("1")}));
    });
    it('should fail support to support supported asset', async function () {
      let isSupported = (await this.zkAccountLedger.supportedAsset("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"));
      console.log(isSupported);
      assert(isSupported == 1);
      await utils.assertRevert(this.zkAccountLedger.supportCErc20("0x39aa39c021dfbae8fac545936693ac917d5e7563", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"));
    });
    it('should accept unsupported asset', async function () {
      await this.zkAccountLedger.createAccount("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints("0");
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      await depositEndpoint.sendTransaction({value: utils.toEther("1")});
      await depositEndpoint.depositLegendEth();
      await this.zkAccountLedger.returnToRedeemAddressEth(depositEndpointAddress);
      let legendEthBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5");
      console.log(legendEthBalance.toString());
    });
    it('should support new asset', async function () {
      await this.zkAccountLedger.supportCErc20("0x39aa39c021dfbae8fac545936693ac917d5e7563", "0x7b64f2dea1d527d83ec8e625c6e6e6f8febdd79b");
      let isSupported = await this.zkAccountLedger.supportedAsset("0x7b64f2dea1d527d83ec8e625c6e6e6f8febdd79b");
      assert(isSupported == 1);
    });
  });
  describe('admin and interest', function () {
    it('should fail support to support supported asset', async function () {
      let isSupported = (await this.zkAccountLedger.supportedAsset("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5"));
      assert(isSupported == 1);
      await utils.assertRevert(this.zkAccountLedger.supportCEther("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5"));
    });
    it('should reject non-admin update', async function () {
      await utils.assertRevert(this.zkAccountLedger.supportCEther("0x7b64f2dea1d527d83ec8e625c6e6e6f8febdd79b", {from: accounts[1]}));
      await utils.assertRevert(this.zkAccountLedger.supportCErc20("0x7b64f2dea1d527d83ec8e625c6e6e6f8febdd79b", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", {from: accounts[1]}));
      await utils.assertRevert(this.zkAccountLedger.setLegendPool("0x7b64f2dea1d527d83ec8e625c6e6e6f8febdd79b", {from: accounts[1]}));
      await utils.assertRevert(this.zkAccountLedger.updateLegendCut("5", {from: accounts[1]}));
    });
    it('should sweep interest', async function () {
      await this.zkAccountLedger.createAccount("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints(0);
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      let usdc = await this.erc20.balanceOf("0x0Bc57B1f2A47bfb031f4F277E82F0E4AE79f1B18");
      console.log(usdc.toString());
      await this.erc20.transfer(depositEndpointAddress, "100000000", {from: "0x0Bc57B1f2A47bfb031f4F277E82F0E4AE79f1B18"});
      let erc20Balance = await this.erc20.balanceOf(depositEndpointAddress);
      console.log(erc20Balance.toString());
      await depositEndpoint.depositLegendErc20(this.erc20.address);
      await this.zkAccountLedger.mintCErc20(this.erc20.address);

      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});
      await depositEndpoint.sendTransaction({value: utils.toEther("0")});

      await this.zkAccountLedger.sweepInterestErc20(this.erc20.address);
    });
  });
  describe('payout distribution', function () {
    it('should distribute eth funds', async function () {
      await this.zkAccountLedger.createAccount("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints(0);
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      let depositEndpointBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5");
      console.log(depositEndpointBalance.toString())
      await depositEndpoint.sendTransaction({value: utils.toEther("1")});
      await depositEndpoint.depositLegendEth();
      await this.payoutPool.sendTransaction({value: utils.toEther("1")});
      await this.payoutPool.distributeFundsEth(depositEndpointAddress, "10", "0123", {from: admin});
      let legendEthBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5");
      assert(legendEthBalance.toString() == "1000000000000000000");
    });
    it('should distribute erc20 funds', async function () {
      await this.zkAccountLedger.createAccount("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", accounts[3], n.toString(), V, salt, version);
      let depositEndpointAddress = await this.zkAccountLedger.depositEndpoints(0);
      let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
      let depositEndpointBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
      console.log(depositEndpointBalance.toString());
      await this.erc20.transfer(depositEndpointAddress, "100", {from: "0x0Bc57B1f2A47bfb031f4F277E82F0E4AE79f1B18"});
      let erc20Balance = await this.erc20.balanceOf(depositEndpointAddress);
      console.log(erc20Balance.toString());
      await depositEndpoint.depositLegendErc20(this.erc20.address);
      await this.zkAccountLedger.mintCErc20(this.erc20.address);
      await this.erc20.transfer(this.payoutPool.address, "100", {from: "0x0Bc57B1f2A47bfb031f4F277E82F0E4AE79f1B18"});
      console.log(admin);
      console.log( await this.payoutPool.admin());
      await this.payoutPool.distributeFundsErc20(depositEndpointAddress, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "10", "0123", {from: admin});
      let legendBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
      assert(legendBalance.toString() == "110");
    });
  });
});
