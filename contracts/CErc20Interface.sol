pragma solidity ^0.5.8;

interface CErc20Interface {

    function mint(uint mintAmount) external returns (uint);

    function redeem(uint redeemTokens) external returns (uint);

    function redeemUnderlying(uint redeemAmount) external returns (uint);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrow() external returns (uint);

    function repayBorrowBehalf(address borrower) external returns (uint);

    function balanceOfUnderlying(address owner) external returns (uint);
}



