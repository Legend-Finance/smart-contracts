pragma solidity ^0.5.8;

import "./EIP20Interface.sol";
import "./ZkAccountLedgerInterface.sol";


contract DepositEndpoint {

    /**
     * @notice Interface contract for zkAccountLedger
     */
    ZkAccountLedgerInterface zkAccountLedger;

    /**
     * @notice Construct user's deposit endpoint
     * @dev Called from zkAccountLedger to create a user's account
     */
    constructor () public {
        zkAccountLedger = ZkAccountLedgerInterface(msg.sender);
    }

    /**
     * @notice Restricts functionality while zkAccount ledger is paused
     */
    modifier notPaused() {
        require(zkAccountLedger.isPaused() == false);
        _;
    }

    /**
     * @notice Fallback function accepts Ether
     * @dev Callable while zkAccountLedger is not paused
     */
    function () external payable notPaused { require(msg.data.length == 0); }

    /**
     * @notice Transfer total `asset` balance of this contract into zkAccountLedger
     * @dev Deposit information is recorded in zkAccountLedger
     * @param asset The address of an ERC20 asset
     * @return bool 1 for success
     */
    function depositLegendErc20(address asset) public returns (bool) {
        EIP20Interface token = EIP20Interface(asset);
        uint256 amount = token.balanceOf(address(this));
        if (token.approve(address(zkAccountLedger), amount) && zkAccountLedger.depositErc20(address(this), asset, amount) == 0) {
            return true;
        } else {
        return false;
        }
    }

    /**
     * @notice Trasnfers total Ether balance of this contract to zkAccount ledger
     * @dev Deposit information is recorded in zkAccountLedger
     * @return bool 1 for success
     */
    function depositLegendEth() public returns (bool) {
        uint256 amount = address(this).balance;

        if (zkAccountLedger.depositEth.value(amount)(address(this)) == 0) {
            return true;
        } else {
            return false;
        }
    }
}
