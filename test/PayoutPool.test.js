const utils = require('./Utils.js');

const PayoutPool = artifacts.require('PayoutPool');
const CErc20 = artifacts.require('CErc20Interface');
const Erc20 = artifacts.require('EIP20Interface');

contract('PayoutPool', function ([admin, ...accounts]) {

  beforeEach(async function () {
    this.token = await Erc20.at("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"); //USDC
    this.payoutPool = await PayoutPool.new();
    assert(await this.payoutPool.admin() == admin);
  });

  describe('asset support', function () {
    it('should properly check asset balance', async function () {
      await this.payoutPool.setMSC(accounts[4]);
      await this.token.deposit({value: 1000000000000000000, from: admin});
      await this.token.transfer(this.payoutPool.address, 1000000000000000000, {from: admin});
      const checkBalance = await this.payoutPool.checkAssetBalance(this.token.address);
      const assetBalance = await this.token.balanceOf(this.payoutPool.address);
      assert.equal(checkBalance.toNumber(), assetBalance.toNumber());
    });
    it('should not allow non-admin to setMSC', async function() {
      await this.payoutPool.setMSC(accounts[4], {from: accounts[4]});
      assert(await this.payoutPool.legendMSC() == 0x0);
    });
    it('should accept and transfer ERC20 funds', async function() {
      await this.payoutPool.setMSC(accounts[4], {from: admin});
      await this.token.deposit({from: admin, value: 10});
      await this.token.transfer(this.payoutPool.address, 10, {from: admin});
      await this.payoutPool.distributeFunds(accounts[3], this.token.address, 5);
      assert(await this.token.balanceOf(accounts[3]) == 5);
    });
    it('should distribute funds to multiple addresses', async function() {
      await this.token.deposit({from: admin, value: 100000});
      await this.token.transfer(this.payoutPool.address, 100000, {from: admin});
      console.log( await this.token.balanceOf(this.payoutPool.address));
      console.log( await this.token.balanceOf(admin));
      console.log( await this.token.balanceOf(accounts[2]));
      console.log(admin);
      console.log( await this.payoutPool.admin());
      await this.payoutPool.distributeFundsList([accounts[0], accounts[1], accounts[2]], [10, 10, 100], [this.token.address, this.token.address, this.token.address], {from: admin});
      console.log( await this.token.balanceOf(this.payoutPool.address));
      console.log( await this.token.balanceOf(accounts[1]));
      console.log( await this.token.balanceOf(accounts[2]));

    })

  });

});
