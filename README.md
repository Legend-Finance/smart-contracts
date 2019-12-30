# Legend Finance

> This document introduces the smart contracts used in the [Legend Finance application.](https://legend.finance/) These contracts are being tested during our current beta release. Production contracts will be audited by a 3rd party and audit results will be posted here.



Upgrade your crypto savings! Hold a Legend Bond for a daily chance to win $20.

Our draw is held at 5:00 PM PST Mon-Fri. Currently, all Legend bondholders have an equal chance of winning and are automatically re-entered every day. One bondholder is randomly selected each day to receive the 20 USD Coin (USDC) prize, equivalent to $20. USDC is a type of cryptocurrency that is referred to as a stablecoin. You can always redeem 1 USDC for exactly $1.00, giving it a stable price. Each USDC is backed by 1 US dollar, which is held in a bank account. See the latest [USDC Reserve Attestation Report](https://www.centre.io/pdfs/attestation/grant-thornton_circle_usdc_reserves_20191114.pdf).

All of the USDC sent to Legend Bonds goes directly to [Compound Finance](https://compound.finance/). This generates interest to fund our daily draw prize and support our operations. You can redeem your Legend Bond at any time, with just 1-click.


# Application Overview
![](https://i.imgur.com/0girmUx.png)

Legend integrates with [Coinbase Connect](https://developers.coinbase.com/docs/wallet/coinbase-connect), using the OAuth standard. Users can sign in with their existing Coinbase account to directly deposit into Legend Bonds without requiring a web 3.0 wallet. USDC deposited into Legend Bonds is supplied to the [Compound protocol](https://github.com/compound-finance/compound-protocol) to generate interest. Legend Bonds are registered with the user's Coinbase USDC wallet address and can only be redeemed back to that address. During bond creation, we generate Feige-Fiat-Shamir (FFS) parameters for use as an optional Recovery Code. This code may be used by bondholders to redeem their funds by directly interacting with our smart contracts, without requiring the Legend Finance web application.



# Smart Contracts
![](https://i.imgur.com/t7Qc0ft.png)


The Legend Finance application is built on [Ethereum](https://github.com/ethereum/ethereum-org-website) and works with established decentralized finance (DeFi) protocols. Ethereum allows us to write transparent, auditable, and autonomous smart contracts that control digital currency, run exactly as programmed, and are available anywhere in the world.

The Legend Finance application is based on the following smart contracts:

[**`ZkAccountLedger`**](https://github.com/Legend-Finance/smart-contracts#zkaccountledger)
Operates the general accounting logic of the application.

[**`PayoutPool`**](https://github.com/Legend-Finance/smart-contracts#payoutpool)
Stores and distributes assets to award bondholders.

[**`DepositEndpoints`**](https://github.com/Legend-Finance/smart-contracts#depositendpoint)
Accepts funds deposited from 3rd party applications and forwards to `ZkAccountLedger`.

Together these smart contracts guarantee:
1. Legend never takes custody of user funds.
2. Legend directly supplies user funds to the Compound protocol.
3. Legend Bonds can only be redeemed back to a user's Coinbase USDC wallet address.
4. A daily prize is paid to one randomly selected bondholder and recorded on-chain.
5. A Recovery Code based on Feige-Fiat-Shamir (FFS) is generated for every bondholder.




## Technical Overview

### `ZkAccountLedger`

`ZkAccountLedger` is responsible for:
1. [Creating Accounts](https://github.com/Legend-Finance/smart-contracts#creating-accounts)
2. [Processing Deposits and Supplying Assets to Compound Protocol](https://github.com/Legend-Finance/smart-contracts#processing-deposits-and-supplying-assets-to-compound-protocol)
3. [Withdrawing to Redeem Address](https://github.com/Legend-Finance/smart-contracts#withdrawing-to-redeem-address)
4. [Sweeping Interest from Compound Protocol](https://github.com/Legend-Finance/smart-contracts#sweeping-interest-from-compound-protocol)



#### Creating Accounts
Legend Bonds are represented on-chain as account entries in `ZkAccountLedger`. These accounts are created when a user is on-boarded to the Legend Finance application.
```javascript
createAccount(address assetAddress, address payable recoveryAddress, uint128 n, uint128[] verificationParams, bytes32 salt, uint16 version) → uint256, address (public)
```
This function creates a new `DepositEndpoint` and an account entry for each user.

`recoveryAddress` must be able to accept assets of type `assetAddress`.

`verificationParams` are generated off-chain using the [Legend FFS library](https://www.npmjs.com/package/@cryptolegend/legend_feige_fiat_shamir). `n`, `salt`, `version` and `verificationParams`are used in FFS authentication. Be sure to submit the same `n`, `salt`, `version` and `verificationParams`, otherwise a user’s funds may only be redeemed by using an admin key.

```javascript
mapping (address => uint128[]) private zkVerificationParams
mapping (address => uint128) private zkModBases
```
FFS verification parameters are stored in these mappings during account creation.


Learn more about `DepositEndpoint` in the [`DepositEndpoint`](https://github.com/Legend-Finance/smart-contracts#depositendpoint) section.

#### Processing Deposits and Supplying Assets to Compound Protocol

![](https://i.imgur.com/jsQgexr.png)

`ZkAccountLedger` processes deposits from the user's `DepositEndpoints` and supplies those assets to the Compound protocol through the minting of cTokens, which accumulate interest every block.



```javascript
depositEth(address depositEndpoint) → uint256 (public)
```
This function deposits `msg.value` of ETH from `depositEndpoint`, records a balance update for `depositEndpoint` and mints cETH via the cETH contract.
```javascript
depositErc20(address depositEndpoint, address asset, uint256 amount) → uint256 (public)
mintCErc20(address asset) → uint256 (public)
```
Together, these functions deposit `amount` of `asset` from `depositEndpoint`, record a balance update for `depositEndpoint`, and mint CErc20 of `asset`. Separating deposit and mint, allows a user to recover un-supported funds that may have accidentally been sent to Legend, since not every Erc20 has a corresponding cToken.

```javascript
event BalanceUpdated(address depositEndpoint, address asset, uint256 amount, uint256 newBalance, uint256 blockNumber, uint256 timestamp)
```
A `BalanceUpdated` event is fired for every deposit and withdrawal.
```javascript
mapping (address => mapping (address => uint256)) public assetBalance
```
Asset balances are updated in `assetBalance`. Call `assetBalance(depositEndpoint, asset)` on `ZkAccountLedger` to obtain a user's `asset` balance.




#### Withdrawing to Redeem Address
Assets can ONLY be withdrawn back to a user’s `redeemAddress`. Withdrawals can be executed with an admin function or through FFS authentication.




##### `redeemAddress`
`ZkAccountLedger` can store one `redeemAddress` per asset for each user. For USDC Legend Bonds, a user's `redeemAddress` is their Coinbase USDC wallet address. As a security measure, `redeemAddress` is immutable, which guarantees that withdrawing assets of each type may only be sent to the `redeemAddress` of that asset type.

```javascript
mapping (address => mapping (address => address payable)) public redeemAddress
```
For each user, a public address is locked down in this data structure per asset type. Once set, this becomes the only address to which a user may withdraw the corresponding asset type. To check a user’s `redeemAddress` for a particular asset type, call `redeemAddress(depositEndpointAddress, assetAddress)` on `ZkAccountLedger`.

##### Admin Assisted Withdrawals
![](https://i.imgur.com/2LUJqqg.png)

This is the primary and most convenient way for users to redeem bonds and does not require the use of a Recovery Code. Admin assisted withdrawals allow users to redeem funds back to their stored `redeemAddress` through the Legend Finance web application.

```javascript
returnToRedeemAddressErc20(address depositEndpoint, address asset) → uint256 (public)

returnToRedeemAddressEth(address depositEndpoint) → uint256 (public)
```
These functions perform admin assisted withdrawals, executing a complete withdrawal of the desired funds back to the user’s stored `redeemAddress`.

##### Feige-Fiat-Shamir (FFS) Withdrawals

![](https://i.imgur.com/DBqvTwd.png)


FFS withdrawals allow users to withdraw their funds back to their `redeemAddress` without using the Legend Finance web application. This requires the user's Recovery Code and use of the Legend FFS library.

FFS withdrawals are done in 3 steps:
1) `beginAuthentication` - opens an FFS proof session
2) `createAuthParams` - generates authentication parameters
3) `withdrawErc20`/`withdrawEth` - initiates a withdrawal

```javascript
beginAuthentication(address depositEndpoint, uint256 x) → uint256 (public)
```
This function starts the FFS authentication process and sets up the smart contract to anticipate an FFS zero-knowledge proof. `ZkAccountLedger` records `x` (calculated off-chain using the  Legend FFS Library), current block number, and the public key for the sender of the withdrawal transaction. The public key is stored to prevent bad actors from supplying an incorrect proof, in an attempt to disrupt the withdrawal process.
```javascript
createAuthParams(address depositEndpoint, uint256 authIndex) → uint32[] params (public)
```
This function generates authentication parameters, preparing `ZkAccountLedger` to receive `y` and finish the proof process.

```javascript
withdrawErc20(uint256 y, address depositEndpoint, address asset, uint256 amount, uint256 authIndex) → uint256 (public)

withdrawEth(uint256 y, address depositEndpoint, uint256 amount, uint256 authIndex) → uint256 (public)
```
These functions perform FFS based withdrawal, sending the specified assets back to the user’s `redeemAddress`. The proof `y` needs to be generated off-chain using the [Legend FFS library](https://www.npmjs.com/package/@cryptolegend/legend_feige_fiat_shamir).


##### Supporting Withdrawals of New Asset Types
Users start with one `redeemAddress` that corresponds to their Legend Bond’s asset type (USDC is currently supported). `ZkAccountLedger` supports the addition of new `redeemAddresses` for additional asset types. This will allow Legend to add new asset type bonds in the future (e.g. DAI). It also facilitates the recovery of funds in case a user accidentally sends an un-supported asset type to a Legend Bond (it happens…).

As with executing withdrawals, the two ways of adding new `redeemAddresses` are through an admin function or through FFS authentication.
```javascript
adminAddRedeemAddress(address depositEndpoint, address asset, address payable recoveryAddress) → uint256 (public)
```
This function allows the Legend admin to add a `redeemAddress` to support a new asset type for a given `depositEndpoint`.
```javascript
addRedeemAddress(uint256 y, address depositEndpoint, address asset, address payable recoveryAddress, uint256 authIndex) → uint256 (public)
```
This function allows a user to add a `redeemAddress` for a new asset type to their account. It requires FFS authentication, and is meant for users who want to interact with Legend contracts directly. Make sure `redeemAddress` is able to accept assets of the specified type.

#### Sweeping Interest from Compound Protocol

`ZkAccountLedger` forwards funds to Compound protocol, accumuluating interest every block. That interest is periodically swept into our `PayoutPool`.


```javascript
sweepInterestErc20(address asset) → uint256 (public)

sweepInterestEth() → uint256 (public)
```
These functions calculate and sweep the interest generated from the corresponding Compound cTokens into the `PayoutPool`.

### `PayoutPool`
`PayoutPool` is built to receive and send ETH or Erc20 tokens. It is responsible for distributing assets to Legend bond holders, and recording payout events.

A Legend admin may call the following functions on `PayoutPool` to execute a distribution:
```javascript
distributeFundsErc20(address payable winner, address asset, uint256 amount, uint64 payoutId) → uint256 (public)
```
This function allows a Legend admin to distribute an Erc20 `asset` to one `winner`.  The `asset` is transferred to the `DepositEndpoint` and forwarded into `ZkAccountLedger`. `winner` must be a `DepositEndpoint` address and must be recorded in `ZkAccountLedger`.
```javascript
distributeFundsEth(address payable winner, uint256 amount, uint64 payoutId) → uint256 (public)
```
This allows a Legend admin to distribute ETH to one `winner`.  The ETH is transferred to the `DepositEndpoint` and forwarded into `ZkAccountLedger`. `winner` must be a `DepositEndpoint` address and must be recorded in `ZkAccountLedger`.

```javascript
event PayoutIssued(address winner, uint64 id, address asset, uint256 amount, uint256 blockNumber, uint256 timestamp)
```
This event is fired during distributions and logs distribution data.


### `DepositEndpoint`


Coinbase (along with many other third party applications) limit the amount of gas paid when sending ETH to prevent triggering potentially malicious fallback functions.

Another challenge is that assets from Coinbase can arrive from a different public address for the same user on every deposit. That makes it impossible to link deposits back to a particular user in our system.

To solve these issues, Legend creates a `DepositEndpoint` for each user.

`DepositEndpoint` addresses are used as identifiers for recording a user's account information, such as balances, FFS parameters, and redeem addresses.

A user’s balance is updated when `ZkAccountLedger` receives an ETH or Erc20 deposit from their `DepositEndpoint`.

```javascript
depositLegendErc20(address asset) → bool (public)
```
This function transfers the total `asset` balance of `DepositEndpoint` into `ZkAccountLedger`.
```javascript
depositLegendEth() → bool (public)
```
This function transfers the total ETH balance of `DepositEndpoint` into `ZkAccountLedger`.

When fund are transferred into `ZkAccountLedger`, a `BalanceUpdated` event is fired.
