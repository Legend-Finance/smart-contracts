pragma solidity ^0.5.8;


interface ZkAccountLedgerInterface {

    function depositErc20(address depositEndpoint, address asset, uint amount) external returns (uint);

    function depositEth(address depositEndpoint) external payable returns (uint);

    function isPaused() external view returns (bool);

}
