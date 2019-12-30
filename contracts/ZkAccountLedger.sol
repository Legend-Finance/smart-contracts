pragma solidity ^0.5.8;

import "./CEtherInterface.sol";
import "./CErc20Interface.sol";
import "./DepositEndpoint.sol";
import "./Math.sol";


contract ZkAccountLedger is Math {

    /**
     * @notice Interface for Compound Ether
     */
    CEtherInterface public cEther;

    /**
     * @notice Public address of admin key
     * @dev Used in admin gated functions
     */
    address public admin;

    /**
     * @notice Address of payout pool
     * @dev Eventual destination of interest scraped from Compound.
     *      Used for distributing winnings
     */
    address payable public payoutPool;

    /**
     * @notice Address of Legend pool
     * @dev Used for holding funds of Legend Finance
     */
    address payable public legendPool;

    /**
     * @notice List of supported cToken addresses
     */
    address[] public supportedCTokens;

    /**
     * @notice List of deposit endpoint addresses
     * @dev These are also used as user ids
     */
    address[] public depositEndpoints;

    /**
     * @notice Deposits are paused when true
     */
    bool public paused;

    /**
     * @notice Percentage of interest scraped into Legend pool
     * @dev This has 0.001 granularity and is slicing a percentage of the interest generated
            i.e. 1 = 0.1% of the interest generated, 10 == 1%, and so on.
     */
    uint8 public legendCut;

    /**
     * @notice Keeps track of users' verification params
     * @dev These are used in ffs withdrawals and are for users who want to use our contracts
     *      outside of the Legend web application
     */
    mapping (address => uint128[]) private zkVerificationParams;

    /**
     * @notice Salt used when generating verifivation params off-chain
     */
    mapping (address => bytes32) public siSalt;

    /**
     * @notice Keeps track of the total amount owed to all accounts
     * @dev Allows Legend to calculate the interest generated from Compound
     */
    mapping (address => uint256) public totalAssetBalance;

    /**
     * @notice User asset balances
     * @dev Mapping of userId (depositEndpoint address) to ERC20 address to amount owned
     */
    mapping (address => mapping (address => uint256)) public assetBalance;

    /**
     * @notice Maps CErc20 Address to underlying ERC20 asset address
     */
    mapping (address => address) public underlyingAddress;

    /**
     * @notice Maps underlying ERC20 asset address to its corresponding CErc20 address
     */
    mapping (address => address) public cTokenAddress;

    /**
     * @notice Tracks ffs withdrawal attempts
     * @dev Maps auth index to public address of authenticator per depositEndpoint.
     *      i.e. authSession[0xUser][authIndex] = 0xAuthKey
     */
    mapping (address => mapping (uint256 => address)) public authSessionAddress;

    /**
     * @notice Locks down the only address a user may withdraw their funds into per asset
     * @dev Maps deposit endpoint to underlying asset to recovery address. Using address(0x0) for ether
     *      redeemAddress[depositEndpoint][assetAddress] = recoveryAddress
     */
    mapping (address => mapping (address => address payable)) public redeemAddress;

    /**
     * @notice Mod bases used in each user's ffs withdrawal
     */
    mapping (address => uint128) private zkModBases;

    /**
     * @notice Records x used in ffs withdrawals
     * @dev Maps user to session attempt to x. i.e sessionX[depositEndpoint][authIndex] = x
     */
    mapping (address => mapping (uint256 => uint256)) private sessionX;

    /**
     * @notice Block number used for ffs withdrawal attempt
     * @dev This is used to generate a random seed during ffs withdrawals. Must be greater than the block
     *      number x was committed.
     */
    mapping (address => mapping (uint256 => uint256)) private sessionBlockNumber;

    /**
     * @notice Authorization params generated during an ffs withdrawal
     * @dev Maps user to auth attempt session to auth params.
            i.e. authParams[depositEndpoint][authIndex] = sessionAuthParams
     */
    mapping (address => mapping (uint256 => uint32[])) public authParams;

    /**
     * @notice Index of current ffs withdrawal attempt
     */
    mapping (address => uint256) private currentAuthIndex;

    /**
     * @notice Tracks whether Erc20 asset address is supported
     * @dev supportedAsset[erc20Address] = 1 is supported
     */
    mapping (address => bool) public supportedAsset;

    /**
     * @notice Tracks ffs version used when creating a user's account
     */
    mapping (address => uint16) public ffsVersion;

    /**
     * @notice Triggered when an asset is supported
     */
    event AssetSupported(address asset, address cToken, uint256 blockNumber, uint256 timestamp);

    /**
     * @notice Triggered when a user's balance updates
     */
    event BalanceUpdated(address depositEndpoint, address asset, uint256 amount, uint256 newBalance, uint256 blockNumber, uint256 timestamp);

    /**
     * @notice Triggered when a user's account is created
     */
    event DepositEndpointCreated(address asset, address depositEndpoint, uint256 blockNumber, uint256 timestamp);

    /**
     * @notice Constructs a new zkAccountLedger
     */
    constructor() public {
        admin = msg.sender;
        paused = false;
        legendCut = 0;
    }

    /**
     * @notice Fallback function to accept Ether deposits
     */
    function () external payable {
        require(msg.data.length == 0);
    }

    /**
     * @notice Adds support for and sets Compound Ether address
     * @dev Locks in the Compound Ether address. Can only be called once
     * @param cEtherAddress Address of Compound Ether
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function supportCEther(address payable cEtherAddress) public returns (uint) {
        if (validateAdmin() == 0) {
            if (address(cEther) == address(0x0)) {
                cEther = CEtherInterface(cEtherAddress);
                supportedCTokens.push(address(cEther));
                // using cEth address for ether, since doesn't have an underlying address
                supportedAsset[cEtherAddress] = true;

                emit AssetSupported(cEtherAddress, cEtherAddress, block.number, block.timestamp);

                return error(Errors.NO_ERROR);

            } else { return error(Errors.CONTRACT_ALREADY_SET); }
        }

        return validateAdmin();
    }

    /**
     * @notice Adds support for an Erc20 asset and sets its Compound token address
     * @param cErc20Address Address of Compound Erc20
     * @param asset Address of Erc20 asset
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function supportCErc20(address cErc20Address, address asset) public returns (uint) {
        if (validateAdmin() == 0) {
            if (supportedAsset[asset]) {
                return error(Errors.CONTRACT_ALREADY_SET);
            } else {
                underlyingAddress[cErc20Address] = asset;
                cTokenAddress[asset] = cErc20Address;
                supportedAsset[asset] = true;
                supportedCTokens.push(cErc20Address);
                emit AssetSupported(asset, cErc20Address, block.number, block.timestamp);
            }
        }

        return validateAdmin();
    }

    /**
     * @notice Sets Legend public address
     * @param pool Address of Legend pool
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function setLegendPool(address payable pool) public returns (uint) {
        if (validateAdmin() == 0) {
            legendPool = pool;
        }

        return validateAdmin();
    }

    /**
     * @notice Sets payout pool address
     * @param pool Address of payout pool
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function setPayoutPool(address payable pool) public returns (uint) {
        if (validateAdmin() == 0) {
            payoutPool = pool;
        }

        return validateAdmin();
    }

    /**
     * @notice Creates a new deposit endpoint and account entry for each user
     * @dev Recovery address must be able to accept assets of type `assetAddress`.
     *      Verification params are generated off chain using Legend's ffs library.
     *      Careful when inputting `n`, `salt`, `version` and `verificationParams`,
     *      otherwise funds may only be recovered with the admin key.
     * @param assetAddress Address of Erc20 asset (CEther address is used for Ether)
     * @param recoveryAddress Public address of a user's account outside of Legend
     * @param n Modbase used in ffs withdrawals
     * @param verificationParams Ffs verification params used in ffs withdrawals
     * @param salt Used when generating ffs verification params off-chain
     * @param version Version of ffs used when generating verification params
     */
    function createAccount(address assetAddress, address payable recoveryAddress, uint128 n, uint128[] memory verificationParams, bytes32 salt, uint16 version) public returns (uint, address) {
        require(recoveryAddress != address(0x0), "invalid recovery address");
        DepositEndpoint newDepositEndpoint = new DepositEndpoint();
        address depositEndpoint = address(newDepositEndpoint);
        depositEndpoints.push(depositEndpoint);
        zkVerificationParams[depositEndpoint] = verificationParams;
        redeemAddress[depositEndpoint][assetAddress] = recoveryAddress; // use cEther address for ether
        zkModBases[depositEndpoint] = n;
        siSalt[depositEndpoint] = salt;
        currentAuthIndex[depositEndpoint] = 0;
        ffsVersion[depositEndpoint] = version;

        emit DepositEndpointCreated(assetAddress, depositEndpoint, block.number, block.timestamp);

        return (error(Errors.NO_ERROR), depositEndpoint);
    }

    /**
     * @notice Deposit `amount` of Erc20 at `asset` into Legend
     * @param depositEndpoint Address of user's deposit endpoint
     * @param asset Address of Erc20 asset
     * @param amount The amount of ERC20 asset to be deposited in the lowest denomination of that asset
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function depositErc20(address depositEndpoint, address asset, uint256 amount) public returns (uint) {
        EIP20Interface token = EIP20Interface(asset);

        if (paused) {
            require(token.transferFrom(depositEndpoint, redeemAddress[depositEndpoint][asset], amount), "erc20 failure");
            return error(Errors.PAUSED);
        } else {
            if (token.transferFrom(depositEndpoint, address(this), amount)) {
                assetBalance[depositEndpoint][asset] += amount;
                totalAssetBalance[asset] += amount;

                emit BalanceUpdated(depositEndpoint, asset, amount, assetBalance[depositEndpoint][asset], block.number, block.timestamp);

                return error(Errors.NO_ERROR);
            } else { return error(Errors.INVALID_INPUT); }
        }
    }

    /**
     * @notice Deposit ETH into Legend and forward to compound
     * @param depositEndpoint Address of user's deposit endpoint
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function depositEth(address depositEndpoint) public payable returns (uint) {
        require(address(cEther) != address(0x0) && supportedAsset[address(cEther)]);
        require(mintCEther() == 0, "compound failure");
        assetBalance[depositEndpoint][address(cEther)] += msg.value;
        totalAssetBalance[address(cEther)] += msg.value;  // using cEther address here for underlying eth balance tracking

        emit BalanceUpdated(depositEndpoint, address(cEther), msg.value, assetBalance[depositEndpoint][address(cEther)], block.number, block.timestamp);

        return error(Errors.NO_ERROR);
    }

    /**
     * @notice Mint CEther from all Ether in currently in this contract
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function mintCEther() public payable returns (uint) {
        cEther.mint.value(address(this).balance)(); // Compound reverts upon failure
        return error(Errors.NO_ERROR);
    }

    /**
     * @notice Mint CErc20 from all Erc20 `asset` currently in this contract
     * @param asset Address of Erc20 asset
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function mintCErc20(address asset) public returns (uint) {
        EIP20Interface token = EIP20Interface(asset);
        CErc20Interface cErc20 = CErc20Interface(cTokenAddress[asset]);
        uint amount = token.balanceOf(address(this));
        require(supportedAsset[asset], "asset not supported");

        if (token.approve(address(cErc20), amount) && cErc20.mint(amount) == 0) {
            return uint(Errors.NO_ERROR);
        } else { return error(Errors.COMPOUND_ERROR); }
    }

    /**
     * @notice Ffs withdrawal that sends assets back to user's redeemAddress
     * @dev Must first begin authentication, then create auth params before generating y off-chain
     * @param y Calculated off-chain from secret and auth params. Required to complete ffs withdrawal,
     *          checked in verification step
     * @param depositEndpoint User's deposit endpoint address
     * @param asset Address of Erc20 asset to withdraw
     * @param amount The amount of Erc20 to be withdrawn in the lowest possible denomination. 0 = full withdrawal
     * @param authIndex Session attempt index
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function withdrawErc20(uint256 y, address depositEndpoint, address asset, uint256 amount, uint256 authIndex) public returns (uint) {
        EIP20Interface token = EIP20Interface(asset);
        CErc20Interface cErc20 = CErc20Interface(cTokenAddress[asset]);
        uint timeoutBlock = sessionBlockNumber[depositEndpoint][authIndex] + 20;
        require(timeoutBlock > block.number, "session timeout");
        if (amount == 0) { amount = assetBalance[depositEndpoint][asset]; }
        require(redeemAddress[depositEndpoint][asset] != address(0x0), "return address doesn't exist");

        if (currentAuthIndex[depositEndpoint] > authIndex) {
            if (assetBalance[depositEndpoint][asset] >= amount) {
                if (verify(zkVerificationParams[depositEndpoint], zkModBases[depositEndpoint], y, depositEndpoint, authIndex)) {
                    if (supportedAsset[asset]){
                        require(cErc20.redeemUnderlying(amount) == 0);
                        assetBalance[depositEndpoint][asset] -= amount;
                        totalAssetBalance[asset] -= amount;
                        require(token.transfer(redeemAddress[depositEndpoint][asset], amount));

                        emit BalanceUpdated(depositEndpoint, asset, amount, assetBalance[depositEndpoint][asset], block.number, block.timestamp);

                        return error(Errors.NO_ERROR);
                    } else {
                        assetBalance[depositEndpoint][asset] -= amount;
                        totalAssetBalance[asset] -= amount;
                        require(token.transfer(redeemAddress[depositEndpoint][asset], amount));

                        emit BalanceUpdated(depositEndpoint, asset, amount, assetBalance[depositEndpoint][asset], block.number, block.timestamp);

                        return error(Errors.NO_ERROR);
                    }
                }
                else { return error(Errors.UNAUTHORIZED); }
            }
            else { return error(Errors.INSUFFICIENT_BALANCE); }
        }
        else { return error(Errors.INVALID_INPUT); }
    }

    /**
     * @notice Ffs withdrawal that sends Ether back to user's redeemAddress
     * @dev Must first begin authentication, then create auth params before generating y off-chain
     * @param y Calculated off-chain from secret and auth params. Required to complete ffs withdrawal,
     *          checked in verification step
     * @param depositEndpoint User's deposit endpoint address
     * @param amount The amount of Ether to be withdrawn in Wei. 0 = full withdrawal
     * @param authIndex Session attempt index
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function withdrawEth(uint256 y, address depositEndpoint, uint256 amount, uint256 authIndex) public returns (uint) {
        uint timeoutBlock = sessionBlockNumber[depositEndpoint][authIndex] + 20;
        require(timeoutBlock > block.number, "session timeout");
        require(redeemAddress[depositEndpoint][address(cEther)] != address(0x0), "return address doesn't exist");
        if (amount == 0) { amount = assetBalance[depositEndpoint][address(cEther)]; }
        if (currentAuthIndex[depositEndpoint] > authIndex) {
            if (assetBalance[depositEndpoint][address(cEther)] >= amount) {
                if (verify(zkVerificationParams[depositEndpoint], zkModBases[depositEndpoint], y, depositEndpoint, authIndex)) {
                    require(cEther.redeemUnderlying(amount) == 0, "compound failure");
                    assetBalance[depositEndpoint][address(cEther)] -= amount;
                    totalAssetBalance[address(cEther)] -= amount;
                    redeemAddress[depositEndpoint][address(cEther)].transfer(amount);

                    emit BalanceUpdated(depositEndpoint, address(0x0), amount, assetBalance[depositEndpoint][address(cEther)], block.number, block.timestamp);

                    return error(Errors.NO_ERROR);
                }
                else { return error(Errors.UNAUTHORIZED); }
            }
            else { return error(Errors.INSUFFICIENT_BALANCE); }
        }
        else { return error(Errors.INVALID_INPUT); }
    }

    /**
     * @notice Starts a withdrawal attempt
     * @dev Commits x, current block number, and public key of user attempting to withdraw funds to a session.
     *      x is calculated off-chain by the attempting user.
     * @param depositEndpoint Address of user's deposit endpoint
     * @param x Calculated off-chain from (r^2) % n.
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function beginAuthentication(address depositEndpoint, uint256 x) public returns (uint) {
        uint256 authIndex = currentAuthIndex[depositEndpoint];
        authSessionAddress[depositEndpoint][authIndex] = msg.sender;
        sessionX[depositEndpoint][authIndex] = x;
        sessionBlockNumber[depositEndpoint][authIndex] = block.number;

        currentAuthIndex[depositEndpoint] += 1;

        return currentAuthIndex[depositEndpoint];
    }

    /**
     * @notice Creates auth params for ffs withdrawals
     * @param depositEndpoint Address of user's deposit endpoint
     * @param authIndex Session id for withdrawal attempt
     * @return authentication params used in ffs withdrawals
     */
    function createAuthParams(address depositEndpoint, uint256 authIndex) public returns (uint32[] memory params) {
        require(sessionBlockNumber[depositEndpoint][authIndex] < block.number && sessionBlockNumber[depositEndpoint][authIndex] != 0, "invalid session");
        uint64 aBits = randomBits(zkVerificationParams[depositEndpoint].length);
        bool hasNon0 = false;
        authParams[depositEndpoint][authIndex] = new uint32[](zkVerificationParams[depositEndpoint].length);

        for (uint256 i = 0; i < zkVerificationParams[depositEndpoint].length; i++) {
            authParams[depositEndpoint][authIndex][i] = uint32(aBits % 2);
            if (authParams[depositEndpoint][authIndex][i] > 0) {
              hasNon0 = true;
            }
        }
        // TODO: do we need to make sure there is a minimum amount of non-zero values?
        if (!hasNon0) {
            authParams[depositEndpoint][authIndex][random(authParams[depositEndpoint][authIndex].length)] = 1;
        }

        return authParams[depositEndpoint][authIndex];
    }

    /**
     * @notice Admin enabled Erc20 withdrawals
     * @dev This is a full withdrawal, and is used when withdrawing from the web application
     * @param depositEndpoint Address of user's deposit endpoint
     * @param asset Address of Erc20 asset to be withdrawn
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function returnToRedeemAddressErc20(address depositEndpoint, address asset) public returns (uint) {
        uint amount = assetBalance[depositEndpoint][asset];
        EIP20Interface token = EIP20Interface(asset);
        CErc20Interface cErc20 = CErc20Interface(cTokenAddress[asset]);
        if (validateAdmin() == 0) {
            require(redeemAddress[depositEndpoint][asset] != address(0x0), "return address doesn't exist");
            if (supportedAsset[asset]) {
                require(cErc20.redeemUnderlying(amount) == 0, "compound failure");
                assetBalance[depositEndpoint][asset] -= amount;
                totalAssetBalance[asset] -= amount;
                require(token.transfer(redeemAddress[depositEndpoint][asset], amount), "compound failure");
                assert(assetBalance[depositEndpoint][asset] == 0);

                emit BalanceUpdated(depositEndpoint, asset, amount, assetBalance[depositEndpoint][asset], block.number, block.timestamp);

                return error(Errors.NO_ERROR);
            } else {
                assetBalance[depositEndpoint][asset] -= amount;
                totalAssetBalance[asset] -= amount;
                require(token.transfer(redeemAddress[depositEndpoint][asset], amount), "erc20 failure");
                assert(assetBalance[depositEndpoint][asset] == 0);

                emit BalanceUpdated(depositEndpoint, asset, amount, assetBalance[depositEndpoint][asset], block.number, block.timestamp);

                return error(Errors.NO_ERROR);
            }
        }

        return validateAdmin();
    }

    /**
     * @notice Admin enabled Ether withdrawals
     * @dev This is a full withdrawal, and is used when withdrawing from the web application
     * @param depositEndpoint Address of user's deposit endpoint
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function returnToRedeemAddressEth(address depositEndpoint) public returns (uint) {
        require(address(cEther) != address(0x0) && supportedAsset[address(cEther)], "unsupported asset");
        uint amount = assetBalance[depositEndpoint][address(cEther)];
        if (validateAdmin() == 0) {
            // redeem underlying Ether before sending to redeemAddress
            require(cEther.redeemUnderlying(amount) == 0, "compound failure");
            require(redeemAddress[depositEndpoint][address(cEther)] != address(0x0), "return address doesn't exist");
            redeemAddress[depositEndpoint][address(cEther)].transfer(amount);
            assetBalance[depositEndpoint][address(cEther)] -= amount;
            totalAssetBalance[address(cEther)] -= amount;
            require(assetBalance[depositEndpoint][address(cEther)] == 0, "INSUFFICIENT_BALANCE");

            emit BalanceUpdated(depositEndpoint, address(0x0), amount, assetBalance[depositEndpoint][address(cEther)], block.number, block.timestamp);

            return error(Errors.NO_ERROR);
        }
        return validateAdmin();
    }

    /**
     * @notice Allows users to add assets to their account
     * @dev This can only add new assets, and requires ffs authentication.
     *      For users who want to interact with Legend contracts outside of the web application.
     *      Make sure `recoveryAddress` is able to interact with the `asset`
     * @param y Calculated off-chain from secret and auth params. Required to complete ffs withdrawal,
     *          checked in verification step
     * @param depositEndpoint Address of user's deposit endpoint
     * @param asset Address of Erc20 asset
     * @param recoveryAddress Public address of user's account outside of legend
     * @param authIndex Session attempt index
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function addRedeemAddress(uint256 y, address depositEndpoint, address asset, address payable recoveryAddress, uint authIndex) public returns (uint) {
        uint timeoutBlock = sessionBlockNumber[depositEndpoint][authIndex] + 20;
        require(timeoutBlock > block.number, "session timeout");
        require(redeemAddress[depositEndpoint][asset] == address(0x0), "cannot replace old recovery address");
        require(verify(zkVerificationParams[depositEndpoint], zkModBases[depositEndpoint], y, depositEndpoint, authIndex), "INVALID_INPUT");
        redeemAddress[depositEndpoint][asset] = recoveryAddress;
        return error(Errors.NO_ERROR);
    }

    /**
     * @notice Allows admin to add a new asset return address to a user's account
     * @dev This can only add new assets. Make sure `recoveryAddress` can interact with `asset`.
     * @param depositEndpoint Address of user's deposit endpoint
     * @param asset Address of Erc20 asset
     * @param recoveryAddress Public address of user's account outside of legend
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function adminAddRedeemAddress(address depositEndpoint, address asset, address payable recoveryAddress) public returns (uint) {
        require(redeemAddress[depositEndpoint][asset] == address(0x0), "cannot replace old recovery address");
        if (validateAdmin() == 0) {
            redeemAddress[depositEndpoint][asset] = recoveryAddress;
            return error(Errors.NO_ERROR);
        } return validateAdmin();
    }

    /**
     * @notice Calculates and sweeps interest generated from Compound Erc20 into payout and Legend pools
     * @param asset Address of Erc20 asset
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function sweepInterestErc20(address asset) public returns (uint) {
        EIP20Interface token = EIP20Interface(asset);
        CErc20Interface cErc20 = CErc20Interface(cTokenAddress[asset]);

        if (validateAdmin() == 0) {
            // withdraw from compound and send to pool contract(s)
            uint compoundAmount = cErc20.balanceOfUnderlying(address(this));
            require(compoundAmount > totalAssetBalance[asset], "no interest accrued");
            uint interest = compoundAmount - totalAssetBalance[asset];
            require(cErc20.redeemUnderlying(interest) == 0, "compound failure");

            if (legendCut > 0) {
                uint256 legendInterest = (legendCut * interest) / 1000;
                require(legendInterest < interest, "legend failure");
                uint256 payoutInterest = interest - legendInterest;
                assert(payoutInterest < interest);
                require(token.transfer(legendPool, legendInterest), "erc20 failure");
                require(token.transfer(payoutPool, payoutInterest), "erc20 failure");
                return error(Errors.NO_ERROR);
            } else {
                require(token.transfer(payoutPool, interest), "erc20 failure");
                return error(Errors.NO_ERROR);
            }
        }

        return validateAdmin();
    }

    /**
     * @notice Calculates and sweeps interest generated from Compound Ether into payout and Legend pools
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function sweepInterestEth() public returns (uint) {
        if (validateAdmin() == 0) {
            uint compoundAmount = cEther.balanceOfUnderlying(address(this));
            require(compoundAmount > totalAssetBalance[address(cEther)], "no interest accrued");
            uint interest = compoundAmount - totalAssetBalance[address(cEther)];
            require(cEther.redeemUnderlying(interest) == 0, "COMPOUND_ERROR");

            if (legendCut > 0) {
                uint256 legendInterest = (legendCut * interest) / 1000;
                assert(legendInterest < interest);
                uint256 payoutInterest = interest - legendInterest;
                assert(payoutInterest < interest);
                legendPool.transfer(legendInterest);
                payoutPool.transfer(payoutInterest);
                return error(Errors.NO_ERROR);
            } else {
                payoutPool.transfer(interest);
                return error(Errors.NO_ERROR);
            }
        }

        return validateAdmin();

    }

    /**
     * @notice Pauses and unpauses deposits into Legend
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function togglePause() public returns (uint) {
        if (validateAdmin() == 0) {
            if (paused) {
                paused = false;
                return error(Errors.NO_ERROR);
            }

            else {
                paused = true;
                return error(Errors.NO_ERROR);
            }
        }

        return validateAdmin();
    }

    /**
     * @notice Updates percentage of interest diverted to Legend pool
     * @param newCut Percentage of cut in 0.1% increments
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function updateLegendCut(uint8 newCut) public returns (uint) {
        if (validateAdmin() == 0) {
            if (newCut > 250) {
                return error(Errors.INVALID_INPUT);
            }
            legendCut = newCut;

            return error(Errors.NO_ERROR);
        }

        return validateAdmin();
    }

    /**
     * @notice Calculates ffs auth params for user interactions with this contract outside of the Legend web application
     * @param depositEndpoint Address of a user's deposit endpoint
     * @param authIndex Auth attempt session id
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function getAuthParams(address depositEndpoint, uint256 authIndex) external view returns (uint32[] memory params) {
        return authParams[depositEndpoint][authIndex];
    }

    /**
     * @notice Helper function to check if deposits are paused
     * @return bool 1 = true
     */
    function isPaused() external view returns (bool) {
        return paused;
    }

    // Internal functions

    /**
     * @notice Helper function to complete ffs authentication
     * @param v User's verification params
     * @param n Mod base
     * @param y Calculated off-chain from user's secret and auth params
     * @param depositEndpoint Address of a user's deposit endpoint
     * @param authIndex Auth attempt session id
     * @return bool 1 = true
     */
    function verify(uint128[] memory v, uint128 n, uint256 y, address depositEndpoint, uint256 authIndex) internal view returns (bool isCorrect) {
        uint256 length = authParams[depositEndpoint][authIndex].length;
        uint256 product = 1;
        uint32[] memory a = authParams[depositEndpoint][authIndex];

        for (uint i = 0; i < length; i++) {
            uint256 vi = v[i];
            product *= (vi ** a[i]);
            product = product % n;
        }
        uint256 rightSide1 = (sessionX[depositEndpoint][authIndex] * product) % n;
        uint256 rightSide2 = (-sessionX[depositEndpoint][authIndex] * product) % n;
        uint256 leftSide = (y**2) % n;

        return (leftSide == rightSide1) || (leftSide == rightSide2);
    }

    /**
     * @notice Helper function; checks if message sender is an admin
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function validateAdmin() internal returns (uint) {
        if (msg.sender != admin) {
            return error(Errors.NOT_ADMIN);
        } else { return error(Errors.NO_ERROR); }
    }

    /**
     * @notice Helper function; calculates random number
     * @return random uint128
     */
    function random(uint256 max) internal view returns (uint128) {
        return uint128(uint256(keccak256(abi.encodePacked(blockhash(block.number - 1)))) % max);
    }

    /**
     * @notice Helper function; calculates random bits
     * @return random uint64
     */
    function randomBits(uint256 bits) internal view returns (uint64) {
        return uint64(uint256(keccak256(abi.encodePacked(blockhash(block.number - 1)))) % (2**bits));
    }

}
