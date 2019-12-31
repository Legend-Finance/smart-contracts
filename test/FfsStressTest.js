const utils = require('./Utils.js');
const Ffs = require('./ffs/ffs.js');
const ZkAccountLedger = artifacts.require('ZkAccountLedger');
const CEther = artifacts.require('CEtherInterface');
const CErc20 = artifacts.require('CErc20Interface');
const Erc20 = artifacts.require('EIP20Interface');
const DepositEndpoint = artifacts.require('DepositEndpoint');


contract('ZkAccountLedger', function ([admin, ...accounts]) {

  beforeEach(async function () {
    this.cEth = await CEther.at("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5");
    this.zkAccountLedger = await ZkAccountLedger.new();
    this.cErc20 = await CErc20.at("0x39aa39c021dfbae8fac545936693ac917d5e7563"); //cUSDC
    this.erc20 = await Erc20.at("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"); //USDC
    await this.zkAccountLedger.supportCEther(this.cEth.address);
    await this.zkAccountLedger.supportCErc20(this.cErc20.address);
    assert(await this.zkAccountLedger.admin() == admin);
  });

  describe('ffs stress test', function () {
    it('create multiple accounts', async function () {

      for (var i = 0; i < 500; i++) {
        let ffs = new Ffs([23, 32, 222, 121], 16, 4, 4);
        let version = 0;

        let n, S, V, salt;
        [n, S, V, salt] = ffs.setup();

        let sign, r, x;
        [sign, r, x] = ffs.initProof(n);

        await this.zkAccountLedger.createAccount(accounts[3], n, V, salt, version);
        let depositEndpointAddress = await this.zkAccountLedger.walletAddresses(i);
        let depositEndpoint = await DepositEndpoint.at(depositEndpointAddress);
        await depositEndpoint.sendTransaction({value: utils.toEther(1)});
        await depositEndpoint.depositLegendEth();

        await this.zkAccountLedger.beginAuthentication(depositEndpointAddress, x);
        await this.zkAccountLedger.createAuthParams(depositEndpointAddress, i);
        let auth = await this.zkAccountLedger.getAuthParams(i);
        let A = auth.map(x => x.toNumber());
        let y = ffs.computeY(r,S,A,n);
        await this.zkAccountLedger.withdrawEth(y, depositEndpointAddress, 1000000000000000000, i);
        let ethBalance = await this.zkAccountLedger.assetBalance(depositEndpointAddress, 0);
        assert(ethBalance == 0);
      }
    });
  });
});

