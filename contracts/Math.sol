pragma solidity ^0.5.8;

import "./ErrorCodes.sol";

contract Math is ErrorCodes {
    function mul(uint a, uint b) internal pure returns (Errors, uint) {
        if (a == 0) {
            return (Errors.NO_ERROR, 0);
        }

        uint c = a * b;

        if (c / a != b) {
            return (Errors.INT_OVERFLOW, 0);
        } else {
            return (Errors.NO_ERROR, c);
        }
    }

    function div(uint a, uint b) internal pure returns (Errors, uint) {
        if (b == 0) {
            return (Errors.ZERO_DENOMINATOR, 0);
        }

        return (Errors.NO_ERROR, a / b);
    }


    function sub(uint a, uint b) internal pure returns (Errors, uint) {
        if (b <= a) {
            return (Errors.NO_ERROR, a - b);
        } else {
            return (Errors.INT_UNDERFLOW, 0);
        }
    }


    function add(uint a, uint b) internal pure returns (Errors, uint) {
        uint c = a + b;

        if (c >= a) {
            return (Errors.NO_ERROR, c);
        } else {
            return (Errors.INT_OVERFLOW, 0);
        }
    }

}
