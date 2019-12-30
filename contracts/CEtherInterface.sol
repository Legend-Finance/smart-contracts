pragma solidity ^0.5.8;

interface CEtherInterface {

    function mint() external payable;

    function redeem(uint redeemTokens) external returns (uint);

    function redeemUnderlying(uint redeemAmount) external returns (uint);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrow() external payable;

    function repayBorrowBehalf(address borrower) external payable;

    function balanceOfUnderlying(address owner) external returns (uint);

    function balanceOf(address owner) external view returns (uint256);

    function () external payable;

}
