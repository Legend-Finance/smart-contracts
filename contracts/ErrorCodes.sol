pragma solidity ^0.5.8;

contract ErrorCodes {

    event Err(uint error);

    enum Errors {
        NO_ERROR,
        INT_OVERFLOW,
        INT_UNDERFLOW,
        ZERO_DENOMINATOR,
        NOT_ADMIN,
        UNAUTHORIZED,
        UNSUPPORTED_ASSET,
        COMPOUND_ERROR,
        CONTRACT_NOT_SET,
        CONTRACT_ALREADY_SET,
        INVALID_INPUT,
        INSUFFICIENT_BALANCE,
        PAUSED
    }

    function error(Errors e) internal returns (uint) {
        emit Err(uint(e));

        return uint(e);
    }

}
