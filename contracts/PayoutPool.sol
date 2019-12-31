pragma solidity ^0.5.8;

import "./EIP20Interface.sol";
import "./ErrorCodes.sol";
import "./ZkAccountLedgerInterface.sol";
import "./DepositEndpoint.sol";


contract PayoutPool is ErrorCodes {

    /**
     * @notice Interface contract for zkAccountLedger
     */
    ZkAccountLedgerInterface zkAccountLedger;

    /**
     * @notice Public address of admin key
     * @dev Used in admin gated functions
     */
    address public admin;

    /**
     * @notice List of supported ERC20 asset addresses
     */
    address[] public supportedAssets;

    /**
     * @notice Supported ERC20 asset addresses mapped to 0 or 1
     * @dev supportedAsset[assetAddress] = 1 is a supported asset
     */
    mapping (address => bool) public supportedAsset;

    /**
     * @notice Records payout information
     */
    event PayoutIssued(address winner, uint64 id, address asset, uint256 amount, uint256 blockNumber, uint256 timestamp);

    /**
     * @notice Construct a new payout pool
     */
    constructor() public {
        admin = msg.sender;
    }

    /**
     * @notice Fallback function to accept Ether transfers
     */
    function () external payable {
        require(msg.data.length == 0);
    }

    /**
     * @notice Writes zkAccountLedger address
     * @dev Used for depositing distributions into users' accounts
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for errors
     */
    function setMSC(address MSC) public returns (uint) {
        if (validateAdmin() == 0) {
            if (address(zkAccountLedger) == address(0x0)) {
            zkAccountLedger = ZkAccountLedgerInterface(MSC);
            return error(Errors.NO_ERROR);
            }
            return error(Errors.CONTRACT_ALREADY_SET);
        }
        return validateAdmin();

    }

    /**
     * @notice Checks ERC20 `asset` balance of this contract
     */
    function checkAssetBalance(address asset) public view returns (uint256) {
        EIP20Interface token = EIP20Interface(asset);
        return token.balanceOf(address(this));
    }

    /**
     * @notice Distributes ERC20 `asset` to one winner address
     * @dev Transfers funds to user's depositEndpoint and forwards those funds into
     *      zkAccountLedger to record the deposit
     * @param winner The depositEndpoint address of the chosen winner
     * @param asset The address of an ERC20
     * @param amount The amount of ERC20 asset to be distributed in the lowest denomination of that asset
     * @param payoutId Unique identifier for the distribution
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for errors
     */
    function distributeFundsErc20(address payable winner, address asset, uint amount, uint64 payoutId) public returns (uint) {
        EIP20Interface token = EIP20Interface(asset);
        DepositEndpoint depositEndpoint = DepositEndpoint(winner);

        if (validateAdmin() == 0) {
            if (token.balanceOf(address(this)) >= amount) {
                if (token.transfer(winner, amount) && depositEndpoint.depositLegendErc20(asset)) {
                    emit PayoutIssued(winner, payoutId, asset, amount, block.number, block.timestamp);
                    return error(Errors.NO_ERROR);
                } return error(Errors.INVALID_INPUT);
            } return error(Errors.INSUFFICIENT_BALANCE);
        } return validateAdmin();
    }

    /**
     * @notice Distributes Ether to one winner address
     * @dev Transfers Ether to user's depositEndpoint and forwards them into
     *      zkAccountLedger to record the deposit
     * @param winner The depositEndpoint address of the chosen winner
     * @param amount The amount of Ether winnings in Wei
     * @param payoutId Unique identifier for the distribution
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function distributeFundsEth(address payable winner, uint amount, uint64 payoutId) public returns (uint) {
        DepositEndpoint depositEndpoint = DepositEndpoint(winner);
        if (validateAdmin() == 0) {
            require(address(this).balance >= amount, "INSUFFICIENT_BALANCE");
            winner.call.value(amount)("");
            require(depositEndpoint.depositLegendEth(), "deposit failure");
            emit PayoutIssued(winner, payoutId, address(0x0), amount, block.number, block.timestamp);
            return error(Errors.NO_ERROR);
        } return validateAdmin();
    }

    /**
     * @notice Calls `distributeFundsErc20` per address listed in `winner`
     * @dev Transfers funds to user's depositEndpoint and forwards those funds into
     *      zkAccountLedger to record the deposit
     * @param winner The depositEndpoint address of the chosen winner
     * @param asset The address of an ERC20
     * @param amount The amount of ERC20 asset to be distributed in the lowest denomination of that asset
     * @param payoutId Unique identifier for the distribution
     * @return uint 0 = success, else an error. Check ErrorCodes.sol for details
     */
    function distributeFundsListErc20(address payable[] calldata winner, address[] calldata asset, uint[] calldata amount, uint64[] calldata payoutId) external returns (uint) {
        if (winner.length == asset.length && winner.length == amount.length && winner.length == payoutId.length) {
            for (uint i = 0; i < winner.length; i++) {
                distributeFundsErc20(winner[i], asset[i], amount[i], payoutId[i]);
            }
        } else { return error(Errors.INVALID_INPUT); }
    }

    /**
     * @notice Checks if message sender is an admin
     * @return uint 0 = success, 4 = not admin
     */
    function validateAdmin() internal returns (uint) {
        if (msg.sender != admin) {
            return error(Errors.NOT_ADMIN);
        } else { return error(Errors.NO_ERROR); }
    }
}
